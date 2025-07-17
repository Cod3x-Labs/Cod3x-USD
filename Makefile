.SILENT:; deployTokenMaker, deployTokenMaker1, deployTokenMakerTest, deployTokenMakerTest1, deployHelper, deployHelperTest

-include .env

prepare:; foundryup && forge clean && forge update && forge install && forge build

build:; forge build
testAll:; forge test -vv

deployAllBase:; forge script script/cdxUsd/CdxUsdAddToLendingPool.s.sol:CdxUsdAddToLendingPool --rpc-url $(BASE_RPC_URL) --private-key $(PRIVATE_KEY) --broadcast --verify --verifier etherscan --verifier-url $(BASE_VERIFIER) --etherscan-api-key $(ETHERSCAN_API_KEY) -vvvv
deployAllBaseTest:; forge script script/cdxUsd/CdxUsdAddToLendingPool.s.sol:CdxUsdAddToLendingPool --rpc-url $(BASE_SEPOLIA_RPC_URL) --private-key $(PRIVATE_KEY) --broadcast --verify --verifier etherscan --verifier-url $(BASE_SEPOLIA_VERIFIER) --etherscan-api-key $(ETHERSCAN_API_KEY) -vvvv
deployAllBaseDry:; forge script script/cdxUsd/CdxUsdAddToLendingPool.s.sol:CdxUsdAddToLendingPool --rpc-url $(BASE_RPC_URL) --private-key $(PRIVATE_KEY) -vvvv
