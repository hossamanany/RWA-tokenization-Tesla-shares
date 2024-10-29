// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script} from "forge-std/Script.sol";
import {dTSLA} from "../src/dTSLA.sol";

contract DeployDTSLA is Script {
    string constant alpacaMintSource = "./functions/sources/alpacaBalance.js";
    string constant alpacaRedeemSource = "";
    uint64 constant subId = 2287; // TODO: Replace with the actual subId

    function run() public {
        string memory mintSource = vm.readFile(alpacaMintSource);

        vm.startBroadcast();
        dTSLA dTsla = new dTSLA(mintSource, subId, alpacaRedeemSource);
        vm.stopBroadcast();
    }
}
