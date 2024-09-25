# Cod3x USD deployment

## Deploy Cod3x USD

### Default value

Find LayerZero EIDs and Endpoints: https://docs.layerzero.network/v2/developers/evm/technical-reference/deployed-contracts#amoy-testnet

Find chain id and rpc: https://chainlist.org/

```java
address cdxUsdUniversalAddress = address(0xC0d37000...);
string name = "Cod3x USD";
string symbol = "cdxUSD";
address delegate = TBD;
address treasury = TBD;
address guardian = TBD;
address _lzEndpoint = Chain_Dependent;
uint32 eid = Chain_Dependent;
uint256 fee = 0; // unit: BPS (default value)
uint256 hourlyLimit = 30_000e18; // unit: cdxUSD (default value)
uint256 limit = -100_000e18; // unit: cdxUSD (default value)
address[] facilitators = [cdxUsdAToken, amo];
```

### Deployment flow on a chain

- Deploy `cdxUSD` contract. (`CdxUsdDeploy.s.sol`)
- Set hourly limit. (`CdxUsdSetLimits.s.sol`)
- Set fee. (`CdxUsdFee.s.sol`)
- Set peer for each already deployed chain. (`CdxUsdSetPeer.s.sol`)
- Set limit for each chain. (`CdxUsdSetLimits.s.sol`)
- Set facilitators. (`CdxUsdAddFacilitator.s.sol`)


```bash
forge script script/cdxUsd/CdxUsdDeploy.s.sol --rpc-url $MAINNET_RPC_URL --private-key $PRIVATE_KEY --etherscan-api-key $ETHEREUM_SCAN_APY_KEY --verify contracts/tokens/CdxUSD.sol:CdxUSD --broadcast
```