# Cod3x USD Audit Report | Cergyk - 03/04/2025

# 1. About cergyk

cergyk is a smart contract security expert, highly ranked accross a variety of audit contest platforms. He has helped multiple protocols in preventing critical exploits since 2022.

# 2. Introduction

A time-boxed security review of the `Cod3x-USD` protocol was done by cergyk, with a focus on the security aspects of the application's smart contracts implementation.

# 3. Disclaimer
A smart contract security review can never verify the complete absence of vulnerabilities. This is
a time, resource and expertise bound effort aimed at finding as many vulnerabilities as
possible. We can not guarantee 100% security after the review or even if the review will find any
problems with your smart contracts. Subsequent security reviews, bug bounty programs and on-
chain monitoring are strongly recommended.

# 4. About Cod3x-USD and scope

Cod3x-USD is a stable coin forked from the GHO model, with the two significant novelties:
- The interest rate is automatically controlled by using a PI controller, making for a flexible control of the token peg.
- The token is natively multichain due to implementing LayerZero's OFT. 

The focus of this review is to assess the security of two consecutive updates:
- Updates following changes made to Cod3x-Lend as part of the fixes of the spearbit review of Cod3x-Lend.
- Upgrading the stable pool used as feedback mechanism for interest rates, from balancer-v2 to balancer-v3.

# 5. Security Assessment Summary

***review commit hash* - [879c4a10](https://github.com/Cod3x-Labs/Cod3x-USD/commit/879c4a1073b8b44689cd9793ddba801d7b6662d1)**

***fixes review commit hash* - [78779b9c](https://github.com/Cod3x-Labs/Cod3x-USD/commit/78779b9c57d1e58a983f6e80084ef435d881c561)**

## Deployment chains

- All EVM chains

## Scope

The following smart contracts are in scope of the audit:

All the contracts under the directory `contracts/` and touched by the updates listed above are in scope 

**DeFi integrations:** Cod3x Lend, Cod3x Vault, Chainlink, Balancer.

# 6. Executive Summary

A security review of the contracts of Reliquary has been conducted during **3 days**.
A total of **5 findings** have been identified and can be classified as below:

### Protocol
| | Details|
|---------------|--------------------|
| **Protocol Name** | Cod3x-USD |
| **Repository**    | [Cod3x-USD](https://github.com/Cod3x-Labs/Cod3x-USD/commit/879c4a1073b8b44689cd9793ddba801d7b6662d1) |
| **Date**          | April 1st 2025 - April 3rd 2025 |
| **Type**          | Stable-coin |

### Findings Count
| Severity  | Findings Count |
|-----------|----------------|
| Critical  |     0           |
| High      |     0           |
| Medium    |     0           |
| Low       |     2           |
| Info/Gas       |     3         |
| **Total findings**| 5         |


# 7. Findings summary
| Findings |
|-----------|
|L-1 BalancerV3Router.addLiquidityHook should use safeTransferFrom|
|L-2 Removing liquidity and adding liquidity using unbalanced kind may revert due to invariant bounds|
|INFO-1 Rename `_to` to `_harvestTo` in zapOutRelic |
|INFO-2 controllerError value is used instead of error in LogPid emitted event|
|INFO-3 CdxUsdOracle should implement IAggregationV3Interface |

# 8. Findings

## L-1 BalancerV3Router::addLiquidityHook should use safeTransferFrom

### Description

BalancerV3Router::addLiquidityHook uses `transferFrom` from the interface IERC20, and will revert with non-compliant tokens such as most notably USDT on mainnet:

[BalancerV3Router.sol#L162-L194](https://github.com/Cod3x-Labs/Cod3x-USD/blob/879c4a1073b8b44689cd9793ddba801d7b6662d1/contracts/staking_module/vault_strategy/libraries/BalancerV3Router.sol#L162-L194):
```solidity
    function addLiquidityHook(
        AddLiquidityHookParams calldata params
    )
        external
        nonReentrant
        onlyVault
        returns (
            uint256[] memory amountsIn,
            uint256 bptAmountOut,
            bytes memory returnData
        )
    {
        ... //@audit add liquidity logic

        for (uint256 i = 0; i < tokens.length; ++i) {
            IERC20 token = tokens[i];
            uint256 amountIn = amountsIn[i];

            if (amountIn == 0) {
                continue;
            }

            //@audit should use safeTransferFrom
            token.transferFrom(params.sender, address(vault), amountIn);
            vault.settle(token, amountIn);
        }
    }
```

Here it would always revert if `USDT` is used on ethereum mainnet as a counter asset for the balancer v3 stable pool.

### Recommendation

`addLiquidityHook` should use safeTransferFrom instead:

[BalancerV3Router.sol#L162-L194](https://github.com/Cod3x-Labs/Cod3x-USD/blob/879c4a1073b8b44689cd9793ddba801d7b6662d1/contracts/staking_module/vault_strategy/libraries/BalancerV3Router.sol#L162-L194):
```diff
    function addLiquidityHook(
        AddLiquidityHookParams calldata params
    )
        external
        nonReentrant
        onlyVault
        returns (
            uint256[] memory amountsIn,
            uint256 bptAmountOut,
            bytes memory returnData
        )
    {
        ...
        
        for (uint256 i = 0; i < tokens.length; ++i) {
            IERC20 token = tokens[i];
            uint256 amountIn = amountsIn[i];

            if (amountIn == 0) {
                continue;
            }

-           token.transferFrom(params.sender, address(vault), amountIn);
+           token.safeTransferFrom(params.sender, address(vault), amountIn);
            vault.settle(token, amountIn);
        }
    }
```

### Cod3x-Labs

Fixed in 78779b9c.

### Cergyk

Fix LGTM.

## L-2 Removing liquidity and adding liquidity using unbalanced kind may revert due to invariant bounds

### Description

The following checks are enforced respectively on adding liquidity and removing liquidity in all pools in balancer v3:

[BasePoolMath.sol#L400-L424](https://github.com/balancer/balancer-v3-monorepo/blob/main/pkg/vault/contracts/BasePoolMath.sol#L400-L424):
```solidity
    /**
     * @notice Validate the invariant ratio against the maximum bound.
     * @dev This is checked when we're adding liquidity, so the `invariantRatio` > 1.
     * @param pool The pool to which we're adding liquidity
     * @param invariantRatio The ratio of the new invariant (after an operation) to the old
     */
    function ensureInvariantRatioBelowMaximumBound(IBasePool pool, uint256 invariantRatio) internal view {
        uint256 maxInvariantRatio = pool.getMaximumInvariantRatio();
        if (invariantRatio > maxInvariantRatio) {
            revert InvariantRatioAboveMax(invariantRatio, maxInvariantRatio);
        }
    }


    /**
     * @notice Validate the invariant ratio against the maximum bound.
     * @dev This is checked when we're removing liquidity, so the `invariantRatio` < 1.
     * @param pool The pool from which we're removing liquidity
     * @param invariantRatio The ratio of the new invariant (after an operation) to the old
     */
    function ensureInvariantRatioAboveMinimumBound(IBasePool pool, uint256 invariantRatio) internal view {
        uint256 minInvariantRatio = pool.getMinimumInvariantRatio();
        if (invariantRatio < minInvariantRatio) {
            revert InvariantRatioBelowMin(invariantRatio, minInvariantRatio);
        }
    }
```

These bounds will be reached if the adding liquidity unbalanced adds approximately 60% to the current invariant (This is equivalent to adding approximately 150% of reserve currently in the pool, which is quite unlikely).

### Recommendation

A modification of the current code is probably not needed, but one should be aware of these limits and document this behavior.

### Cod3x-Labs

Acknowledged.

### Cergyk

Acknowledged.

## INFO-1 Rename `_to` to `_harvestTo` in zapOutRelic 

### Description

The variable _to in Zap::zapOutRelic is a confusing name, because it is only relevant to the harvesting of rewards in reliquary. We suggest to rename it to `_harvestTo`

[Zap.sol#L341-L357](https://github.com/Cod3x-Labs/Cod3x-USD/blob/879c4a1073b8b44689cd9793ddba801d7b6662d1/contracts/staking_module/Zap.sol#L341-L357):
```solidity
function zapOutRelic(
    uint256 _relicId,
    uint256 _amountBptToWithdraw,
    address _tokenToWithdraw,
    uint256 _minAmountOut,
>>  address _to
) external whenNotPaused {
    if (_relicId == 0 || _amountBptToWithdraw == 0 || _minAmountOut == 0 || _to == address(0)) {
        revert Zap__WRONG_INPUT();
    }


    if (!reliquary.isApprovedOrOwner(msg.sender, _relicId)) {
        revert Zap__RELIC_NOT_OWNED();
    }


    /// Reliquary withdraw
    reliquary.withdraw(_amountBptToWithdraw, _relicId, address(_to));
```

### Recommendation

[Zap.sol#L341-L357](https://github.com/Cod3x-Labs/Cod3x-USD/blob/879c4a1073b8b44689cd9793ddba801d7b6662d1/contracts/staking_module/Zap.sol#L341-L357):
```diff
function zapOutRelic(
    uint256 _relicId,
    uint256 _amountBptToWithdraw,
    address _tokenToWithdraw,
    uint256 _minAmountOut,
-   address _to
+   address _harvestTo
) external whenNotPaused {
    if (_relicId == 0 || _amountBptToWithdraw == 0 || _minAmountOut == 0 || _to == address(0)) {
        revert Zap__WRONG_INPUT();
    }


    if (!reliquary.isApprovedOrOwner(msg.sender, _relicId)) {
        revert Zap__RELIC_NOT_OWNED();
    }

    /// Reliquary withdraw
-   reliquary.withdraw(_amountBptToWithdraw, _relicId, address(_to));
+   reliquary.withdraw(_amountBptToWithdraw, _relicId, address(_harvestTo));
```

### Cod3x-Labs

Fixed in 78779b9c.

### Cergyk

Fix LGTM.

## INFO-2 Incorrect error value in emitted event

### Description

The controller error value is used two times in the PidLog event emitted during `calculateInterestRates`:

[CdxUsdIInterestRateStrategy.sol#L302-L325](https://github.com/Cod3x-Labs/Cod3x-USD/blob/879c4a1073b8b44689cd9793ddba801d7b6662d1/contracts/facilitators/cod3x_lend/interest_strategy/CdxUsdIInterestRateStrategy.sol#L302-L325):
```solidity
    //@audit _errI is used two times, should be err, errI
    emit PidLog(currentVariableBorrowRate, stablePoolReserveUtilization, _errI, _errI);
```

Error and controller error usually have different values and should be set accordingly

### Recommendation

[CdxUsdIInterestRateStrategy.sol#L302-L325](https://github.com/Cod3x-Labs/Cod3x-USD/blob/879c4a1073b8b44689cd9793ddba801d7b6662d1/contracts/facilitators/cod3x_lend/interest_strategy/CdxUsdIInterestRateStrategy.sol#L302-L325):
```diff
-    emit PidLog(currentVariableBorrowRate, stablePoolReserveUtilization, _errI, _errI);
+    emit PidLog(currentVariableBorrowRate, stablePoolReserveUtilization, err, _errI);
```

### Cod3x-Labs

Fixed in 78779b9c.

### Cergyk

Fix LGTM.

## INFO-3 CdxUsdOracle could implement IAggregationV3Interface

### Description

CdxUsdOracle is only partially compliant with IAggregationV3Interface (implements `latestRoundData`). Implementing the whole interface could avoid future reverts for example if CdxUsdOracle is casted as `IAggregationV3Interface` for convenience, but a non-implemented method ends up being used. 

[CdxUSDOracle.sol#L11-L13](https://github.com/Cod3x-Labs/Cod3x-USD/blob/879c4a1073b8b44689cd9793ddba801d7b6662d1/contracts/facilitators/cod3x_lend/oracle/CdxUSDOracle.sol#L11-L13):
```solidity
contract CdxUsdOracle {
    /// @dev The fixed price of 1 CdxUSD in USD, with 8 decimal precision (1.00000000).
    int256 public constant CDXUSD_PRICE = 1e8;
```

### Recommendation

Implement the whole `IAggregationV3Interface` interface in CdxUsdOracle.

### Cod3x-Labs

Fixed in 78779b9c.

### Cergyk

Fix LGTM.