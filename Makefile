-include .env

.PHONY: deploy

deploy:; @forge script script/DeployDTSLA.s.sol --sender 0x2c5EFB8915F4A2E90CE5520c815352B751539489 --account defaultKey --rpc-url $(SEPOLIA_RPC_URL) --etherscan-api-key $(ETHERSCAN_API_KEY) --priority-gas-price 1 --verify --broadcast