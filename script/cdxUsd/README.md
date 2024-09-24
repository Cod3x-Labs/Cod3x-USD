# Cod3x USD deployment

## Deploy Cod3x USD

```bash
forge script script/cdxUsd/CdxUsdDeploy.s.sol --rpc-url $MAINNET_RPC_URL --private-key $PRIVATE_KEY --etherscan-api-key $ETHEREUM_SCAN_APY_KEY --verify contracts/tokens/CdxUSD.sol:CdxUSD --broadcast
```