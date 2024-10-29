// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {ConfirmedOwner} from "@chainlink/contracts/src/v0.8/shared/access/ConfirmedOwner.sol";
import {FunctionsClient} from "@chainlink/contracts/src/v0.8/functions/dev/v1_0_0/FunctionsClient.sol";
import {FunctionsRequest} from "@chainlink/contracts/src/v0.8/functions/dev/v1_0_0/libraries/FunctionsRequest.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title dTSLA
 * @dev dTSLA is a tokenized Tesla stock with a 1:1 peg to the underlying asset.
 * @author Hossam Elanany
 */
contract dTSLA is ConfirmedOwner, FunctionsClient, ERC20 {
    using FunctionsRequest for FunctionsRequest.Request;
    using Strings for uint256;

    error dTSLA__NotEnoughCollateral();
    error dTSLA__DoesntMeetMinimumWithdrawalAmount();
    error dTSLA__TransferFailed();

    enum MintOrRedeem {
        MINT,
        REDEEM
    }

    struct dTSLARequest {
        uint256 amountOfToken;
        address requester;
        MintOrRedeem action;
    }

    uint256 constant PRECISION = 1e18;
    address constant SEPOLIA_FUNCTIONS_ROUTER = 0xb83E47C2bC239B3bf370bc41e1459A34b41238D0;
    bytes32 constant DON_ID = hex"66756e2d657468657265756d2d7365706f6c69612d3100000000000000000000";
    address constant SEPOLIA_TSLA_PRICE_FEED = 0xc59E3633BAAC79493d908e63626716e204A45EdF; // This is actually LINK/USD price feed for demo purposes.
    address constant SEPOLIA_USDC_PRICE_FEED = 0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E;
    address constant SEPOLIA_USDC = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6; // TODO: Replace with the actual USDC address
    uint256 constant ADDITIONAL_FEED_PRECISION = 1e10;
    string private s_mintSourceCode;
    string private s_redeemSourceCode;
    uint256 private s_portfolioBalance;
    uint64 immutable i_subId;
    uint32 constant GAS_LIMIT = 300_000;
    uint256 constant COLLATERAL_RATIO = 200; // 200% collateral ratio
    uint256 constant COLLATERAL_PRECISION = 100;
    uint256 constant MINIMUM_WITHDRAWAL_AMOUNT = 100e18; // 100 dTSLA

    mapping(bytes32 requestId => dTSLARequest request) private s_requestIdToRequest;
    mapping(address user => uint256 pendingWithdrawalAmount) private s_userToWithdrawalAmount;

    constructor(string memory mintSourceCode, uint64 subId, string memory redeemSourceCode)
        ConfirmedOwner(msg.sender)
        FunctionsClient(SEPOLIA_FUNCTIONS_ROUTER)
        ERC20("dTSLA", "dTSLA")
    {
        s_mintSourceCode = mintSourceCode;
        s_redeemSourceCode = redeemSourceCode;
        i_subId = subId;
    }

    function sendMintRequest(uint256 amount) external onlyOwner returns (bytes32) {
        FunctionsRequest.Request memory req;
        req.initializeRequestForInlineJavaScript(s_mintSourceCode);
        bytes32 requestId = _sendRequest(req.encodeCBOR(), i_subId, GAS_LIMIT, DON_ID);
        s_requestIdToRequest[requestId] = dTSLARequest(amount, msg.sender, MintOrRedeem.MINT);
        return requestId;
    }

    function _mintFulfillmentRequest(bytes32 requestId, bytes memory response) internal {
        uint256 amountOfTokensToMint = s_requestIdToRequest[requestId].amountOfToken;
        s_portfolioBalance = uint256(bytes32(response));

        // Check if the collateral ratio is still within the limits
        if (_getCollateralRatioAdjustedTotalBalance(amountOfTokensToMint) > s_portfolioBalance) {
            revert dTSLA__NotEnoughCollateral();
        }

        if (amountOfTokensToMint != 0) {
            _mint(s_requestIdToRequest[requestId].requester, amountOfTokensToMint);
        }
    }

    function sendRedeemRequest(uint256 amountdTSLA) external {
        uint256 amountTSLAinUSDC = getUSDCvalueOfUSD(getUSDvalueOfTSLA(amountdTSLA));
        if (amountTSLAinUSDC < MINIMUM_WITHDRAWAL_AMOUNT) {
            revert dTSLA__DoesntMeetMinimumWithdrawalAmount();
        }

        FunctionsRequest.Request memory req;
        req.initializeRequestForInlineJavaScript(s_redeemSourceCode);

        // We're telling our broker (Alpaca) to sell this much dTSLA tokens and refund this much USDC back to the user
        string[] memory args = new string[](2);
        args[0] = amountdTSLA.toString();
        args[1] = amountTSLAinUSDC.toString();
        req.setArgs(args);

        bytes32 requestId = _sendRequest(req.encodeCBOR(), i_subId, GAS_LIMIT, DON_ID);
        s_requestIdToRequest[requestId] = dTSLARequest(amountdTSLA, msg.sender, MintOrRedeem.REDEEM);

        _burn(msg.sender, amountdTSLA);
    }

    function _redeemFulfillmentRequest(bytes32 requestId, bytes memory response) internal {
        uint256 USDCAmount = uint256(bytes32(response));
        if (USDCAmount == 0) {
            uint256 amountOfdTSLABurned = s_requestIdToRequest[requestId].amountOfToken;
            _mint(s_requestIdToRequest[requestId].requester, amountOfdTSLABurned);
            return;
        }

        s_userToWithdrawalAmount[s_requestIdToRequest[requestId].requester] += USDCAmount;
    }

    function withdraw() external {
        uint256 amountToWithdraw = s_userToWithdrawalAmount[msg.sender];
        s_userToWithdrawalAmount[msg.sender] = 0;
        bool success = ERC20(SEPOLIA_USDC).transfer(msg.sender, amountToWithdraw);
        if (!success) {
            revert dTSLA__TransferFailed();
        }
    }

    function fulfillRequest(bytes32 requestId, bytes memory response, bytes memory /*err*/ ) internal override {
        if (s_requestIdToRequest[requestId].action == MintOrRedeem.MINT) {
            _mintFulfillmentRequest(requestId, response);
        } else {
            _redeemFulfillmentRequest(requestId, response);
        }
    }

    function _getCollateralRatioAdjustedTotalBalance(uint256 amountOfTokensToMint) internal view returns (uint256) {
        uint256 calculatedNewTotalValue = getCalculatedNewTotalValue(amountOfTokensToMint);
        return (calculatedNewTotalValue * COLLATERAL_RATIO) / COLLATERAL_PRECISION;
    }

    function getCalculatedNewTotalValue(uint256 addedNumberOfTokens) internal view returns (uint256) {
        // 10 dTSLA tokens + 5 dTSLA tokens = 15 dTSLA tokens * TSLA price ($100) = $1500
        return ((totalSupply() + addedNumberOfTokens) * getTSLAPrice()) / PRECISION;
    }

    function getUSDCvalueOfUSD(uint256 USDAmount) public view returns (uint256) {
        return (USDAmount * getUSDCPrice()) / PRECISION;
    }

    function getUSDvalueOfTSLA(uint256 amountOfdTSLA) public view returns (uint256) {
        return (amountOfdTSLA * getTSLAPrice()) / PRECISION;
    }

    function getTSLAPrice() public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(SEPOLIA_TSLA_PRICE_FEED);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return uint256(price) * ADDITIONAL_FEED_PRECISION; // In order to have a precision of 1e18
    }

    function getUSDCPrice() public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(SEPOLIA_USDC_PRICE_FEED);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return uint256(price) * ADDITIONAL_FEED_PRECISION; // In order to have a precision of 1e18
    }

    function getRequest(bytes32 requestId) external view returns (dTSLARequest memory) {
        return s_requestIdToRequest[requestId];
    }

    function getPendingWithdrawalAmount(address user) external view returns (uint256) {
        return s_userToWithdrawalAmount[user];
    }

    function getPortfolioBalance() external view returns (uint256) {
        return s_portfolioBalance;
    }

    function getSubId() external view returns (uint64) {
        return i_subId;
    }

    function getMintSourceCode() external view returns (string memory) {
        return s_mintSourceCode;
    }

    function getRedeemSourceCode() external view returns (string memory) {
        return s_redeemSourceCode;
    }

    function getCollateralRatio() external pure returns (uint256) {
        return COLLATERAL_RATIO;
    }

    function getCollateralPrecision() external pure returns (uint256) {
        return COLLATERAL_PRECISION;
    }
}
