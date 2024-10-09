# Cod3x USD Audit Report | Cergyk - 03/10/2024


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

Additionally, a staking model has been added on top ReliquaryV2, to which a portion of the interests accrued from CdxUSD borrowing will be attributed to.

Finally a rehypothecation logic has been implemented for LP tokens invested in Reliquary.


# 5. Security Assessment Summary

***review commit hash* - [0346bab2](https://github.com/Cod3x-Labs/Cod3x-USD/commit/0346bab282ba646d0b431c16e7320a894eaf2361)**

***fixes review commit hash* - [8894e7f1](https://github.com/Cod3x-Labs/Cod3x-USD/commit/8894e7f1a3ce5391dcaf8d5396d9f0ea8b1c8c02)**

## Deployment chains

- All EVM chains

## Scope

The following smart contracts are in scope of the audit: (total: `1370 SLoC`)

**DeFi integrations:** Cod3x Lend, Cod3x Vault, Chainlink, Balancer.

- Token
    - `contracts/tokens/CdxUSD.sol` (forked from [gho](https://github.com/aave/gho-core/blob/main/src/contracts/gho/GhoToken.sol))
    - `contracts/tokens/OFTExtended.sol`
- Staking Module
    - Reliquary ([Diff](https://github.com/Cod3x-Labs/Reliquary/compare/master...cdxUSD-staking) since last Cergyk audit. Added: standardized interface for rehypothecation + Relic#1 doesn't increase in maturity)
        - `contracts/staking_module/reliquary/Reliquary.sol`
        - `contracts/staking_module/reliquary/libraries/ReliquaryLogic.sol`
        - `contracts/staking_module/reliquary/libraries/ReliquaryRehypothecationLogic.sol`
    - Vault strategy and Zap
        - `contracts/staking_module/vault_strategy/ScdxUsdVaultStrategy.sol`
        - `contracts/staking_module/vault_strategy/libraries/BalancerHelper.sol`
        - `contracts/staking_module/Zap.sol`
- Facilitator
    - Flash Minter
        - `contracts/facilitators/flash_minter/CdxUSDFlashMinter.sol` (forked from gho [flashminter](https://github.com/aave/gho-core/blob/main/src/contracts/facilitators/flashMinter/GhoFlashMinter.sol))
    - Cod3x Lend
        - `contracts/facilitators/cod3x_lend/interest_strategy/CdxUsdIInterestRateStrategy.sol`
        - `contracts/facilitators/cod3x_lend/oracle/CdxUSDOracle.sol` (forked from gho [oracle](https://github.com/aave/gho-core/tree/main/src/contracts/facilitators/aave/oracle))
        - `contracts/facilitators/cod3x_lend/token/CdxUsdAToken.sol` (forked from gho [aToken](https://github.com/aave/gho-core/blob/main/src/contracts/facilitators/aave/tokens/GhoAToken.sol))
        - `contracts/facilitators/cod3x_lend/token/CdxUsdVariableDebtToken.sol` (forked from gho [debtToken](https://github.com/aave/gho-core/blob/main/src/contracts/facilitators/aave/tokens/GhoVariableDebtToken.sol) without the discount mechanism)

# 6. Executive Summary

A security review of the contracts of Reliquary has been conducted during **2 weeks**.
A total of **16 findings** have been identified and can be classified as below:

### Protocol
| | Details|
|---------------|--------------------|
| **Protocol Name** | Cod3x-USD |
| **Repository**    | [Cod3x-USD](https://github.com/Cod3x-Labs/Cod3x-USD/commit/0346bab282ba646d0b431c16e7320a894eaf2361) |
| **Date**          | August 26th 2024 - September 7th 2024 |
| **Type**          | Stable-coin |

### Findings Count
| Severity  | Findings Count |
|-----------|----------------|
| Critical  |     0           |
| High      |     1           |
| Medium    |     4           |
| Low       |     4           |
| Info/Gas       |     7         |
| **Total findings**| 16         |


# 7. Findings summary
| Findings |
|-----------|
|H-1 CdxUsdInterestRateStrategy::calculateInterestRates Interest rate index is not updated, because liquidityRate is zero|
|M-1 Zap::zapOutRelic should use safeTransfer to avoid reverting when using USDT|
|M-2 CdxUSDAToken::distributeFeesToTreasury Rewards distribution can be grieved by repeated calls |
|M-3 Balancer stable pool can be used to manipulate interest rate in one block|
|M-4 ScdxUsdVaultStrategy::_harvestCore The logic in harvest will revert if rewards are bigger than position in relic#1|
|L-1 ScdxUsdVaultStrategy::_liquidateAllPositions relic #1 can be burnt when emergencyWithdraw is called|
|L-2 Zap::zapOutStakedCdxUSD Zap out enables only imbalanced exit forcing users to pay balancer fee|
|L-3 ScdxUSDVaultStrategy should be able to handle ERC721|
|L-4 Unsafe cast to uint256 in CdxUsdInterestRateStrategy::transferFunction|
|INFO-1 transferFunction positivity check is useless given signature|
|INFO-2 Setters do not emit events in CdxUsdInterestRateStrategy|
|INFO-3 _maxErrIAmp is redundant with _minControllerError|
|INFO-4 OFTExtended hourly rate limit allows for 2\*eidToConfigPtr.hourlyLimit in a 2\*hour window|
|INFO-5 Initialization flow of CdxUSDAToken can be simplified|
|INFO-6 OFTExtended::_debit xChain transfers can fail due to wrong fee take|
|INFO-7 typos and unaccurate comments|

# 8. Findings

## H-1 CdxUsdInterestRateStrategy::calculateInterestRates Interest rate index is not updated, because liquidityRate is zero

### Description
During the calculation of next interest rates in `CdxUsdInterestRateStrategy::calculateInterestRates`, the returned liquidity rate is hardcoded to be zero:

[CdxUsdIInterestRateStrategy.sol#L306]((https://github.com/Cod3x-Labs/Cod3x-USD/blob/0346bab282ba646d0b431c16e7320a894eaf2361/contracts/facilitators/cod3x_lend/interest_strategy/CdxUsdIInterestRateStrategy.sol#L306)):
```solidity
    return (0, currentVariableBorrowRate);
```

This means that during the index updating of the `Cod3x-lend` module, the variable interest index will not be updated, because `currentLiquidityRate`
 would be zero:

[ReserveLogic.sol#L306](https://github.com/Cod3x-Labs/Cod3x-Lend/blob/b007943c2a08d5431c0bde56ec08687ff45903a9/contracts/protocol/libraries/logic/ReserveLogic.sol#L306):
```solidity
    //only cumulating if there is any income being produced
    if (currentLiquidityRate > 0) {
        // updating liquidity index
        ...

        //as the liquidity rate might come only from stable rate loans, we need to ensure
        //that there is actual variable debt before accumulating
        if (scaledVariableDebt != 0) {
            uint256 cumulatedVariableBorrowInterest = MathUtils.calculateCompoundedInterest(
                reserve.currentVariableBorrowRate, timestamp
            );
            newVariableBorrowIndex = cumulatedVariableBorrowInterest.rayMul(variableBorrowIndex);
            require(
                newVariableBorrowIndex <= type(uint128).max,
                Errors.RL_VARIABLE_BORROW_INDEX_OVERFLOW
            );
            reserve.variableBorrowIndex = uint128(newVariableBorrowIndex);
        }
    }
```

### Recommendation
The logic used for Cod3x-Lend in the current scope is forked from AaveV2, and AaveV3 has separate updating for liquidity index and variable interest index. Updating the forked version will solve this issue. 

### Cod3x-Labs
Fixed in [07be4adb9](https://github.com/Cod3x-Labs/Cod3x-USD/commit/07be4adb927050b43241f6d2b77397c4686c6764)

### Cergyk
Fixed.

## M-1 Zap::zapOutRelic should use safeTransfer to avoid reverting when using USDT

### Description
Some weird tokens do not adhere to the `IERC20` interface, this is the case for USDT on `ethereum` mainnet, in which case the `IERC20::transfer` call will always revert.

Unfortunately `IERC20::transfer` is used in `Zap::zapOutRelic` and `Zap::zapOutStakedCdxUSD`. 

### Recommendation
Use `SafeERC20::safeTransfer` instead for the calls at the end of `Zap::zapOutRelic` and `Zap::zapOutStakedCdxUSD`.

[Zap.sol#L246](https://github.com/Cod3x-Labs/Cod3x-USD/blob/0346bab282ba646d0b431c16e7320a894eaf2361/contracts/staking_module/Zap.sol#L246):
```solidity
    IERC20(_tokenToWithdraw).transfer(_to, IERC20(_tokenToWithdraw).balanceOf(address(this)));
```

[Zap.sol#L340](https://github.com/Cod3x-Labs/Cod3x-USD/blob/0346bab282ba646d0b431c16e7320a894eaf2361/contracts/staking_module/Zap.sol#L340):
```solidity
    IERC20(_tokenToWithdraw).transfer(_to, IERC20(_tokenToWithdraw).balanceOf(address(this)));
```

### Cod3x-Labs
Fixed in [b5488b18](https://github.com/Cod3x-Labs/Cod3x-USD/commit/b5488b18600f687ae3b35fc1eb09d869727eb2f6)

### Cergyk
Fixed.


## M-2 CdxUSDAToken::distributeFeesToTreasury Rewards distribution can be grieved by repeated calls 

### Description
In the AToken implementation for CdxUSD, the function `distributeFeesToTreasury` is unpermissioned, and in turn has the permission to call on `RollingRewarder::fund`. This means that anybody can call to `distributeFeesToTreasury`, and since the amount with which `fund` will be called is zero, the existing rewards will be spread again over the next period. This is similar to the vulnerability explained in [L-03](https://www.beirao.xyz/blog/SR7-Reliquary_Staking_Updates).

### Recommendation
Please consider making the call to this function permissioned to a `KEEPER` role.

### Cod3x-Labs
Fixed in [fe029cdf](https://github.com/Cod3x-Labs/Cod3x-USD/commit/fe029cdf2beb25e3d73a8b4a19d463b83b47c0f8)

### Cergyk
Fixed.

## M-3 Balancer stable pool can be used to manipulate interest rate in one block

### Description
The Proportional-Integral control system which is used to control interest rates in Cod3x-USD is based on a Balancer stable-pool. Specifically, the balancer spot liquidity imbalance will be used to determine the next increase/decrease of interest rate.

[CdxUsdIInterestRateStrategy.sol#L340-L354](https://github.com/Cod3x-Labs/Cod3x-USD/blob/0346bab282ba646d0b431c16e7320a894eaf2361/contracts/facilitators/cod3x_lend/interest_strategy/CdxUsdIInterestRateStrategy.sol#L340-L354):
```solidity
    function getCdxUsdStablePoolReserveUtilization() public view returns (uint256) {
        uint256 totalInPool_;
        uint256 cdxUsdAmtInPool_;

        for (uint256 i = 0; i < stablePoolTokens.length; i++) {
            IERC20 token_ = stablePoolTokens[i];
            
            //@audit spot price is used, and manipulatable in one block
            (uint256 cash_,,,) = IBalancerVault(_balancerVault).getPoolTokenInfo(_poolId, token_);
            cash_ = scaleDecimals(cash_, token_);
            totalInPool_ += cash_;

            if (address(token_) == _asset) cdxUsdAmtInPool_ = cash_;
        }

        return cdxUsdAmtInPool_ * uint256(RAY) / totalInPool_;
    }
```

Unfortunately due to the spot price being used, a malicious actor can pay the balancer fee during a few blocks to add a large amount of liquidity in an imbalanced way, and durably influence interest rate of the CdxUSD borrowing. 

### Cod3x-Labs
Acknowledged. We will monitor the staking module to make sure there is no manipulations

### Cergyk
Acknowledged.

### Recommendation

To mitigate this, one can make the increase of interest rates be indexed on a less volatile variable such a TWAP of the liquidity imbalance.

## M-4 ScdxUsdVaultStrategy::_harvestCore The logic in harvest will revert if rewards are bigger than position in relic#1

### Description
`ScdxUsdVaultStrategy` is inheriting from ReaperBaseStrategyv4, which implements a common flow for handling and reinvesting rewards in a generic manner.

During the `non-emergency` flow, a part of the position is liquidated to ensure that the balance of want is big enough to accomodate the `report` to the vault (e.g repay the debt of the vault). However every time the strategy records a profit (balance > allocated), the profit is withdrawn from the position

[ReaperBaseStrategyv4.sol#L162-L180](https://github.com/Cod3x-Labs/Cod3x-Vault/blob/131a1974ab71a6e08eb584cd41b6450a0866105d/src/ReaperBaseStrategyv4.sol#L162-L180):
```
{
    _harvestCore();

    uint256 allocated = IVault(vault).strategies(address(this)).allocated;
    //@audit totalAssets is the sum of assets at hand and assets of the position (relic #1)
    uint256 totalAssets = _estimatedTotalAssets();
    uint256 toFree = MathUpgradeable.min(debt, totalAssets);

    if (totalAssets > allocated) {
        uint256 profit = totalAssets - allocated;
        //@audit toFree is the amount to be withdrawn from the position (relic #1)
>>      toFree += profit;
        roi = int256(profit);
    } else if (totalAssets < allocated) {
        roi = -int256(allocated - totalAssets);
    }

    //@audit the amount is freed to accomodate for vault.report
    //@audit this not always necessary, since balance at hand can be sufficient to accomodate
    //@audit and in some cases it actually can be harmful since toFree can be gt the balance in the position  
>>  (uint256 amountFreed, uint256 loss) = _liquidatePosition(toFree);
    repayment = MathUpgradeable.min(debt, amountFreed);
    roi -= int256(loss);
}
```

Additionally since _harvestCore() implementation does not reinvest the rewards into the position, there is a low probability scenario in which harvesting can be blocked until a sufficient amount is invested in the relic.

Indeed if at any point, the rewards become bigger than the balance of the position in the relic; The call to harvest attempts to withdraw a profit bigger than the balance in the relic and thus reverts. This means that harvest is blocked until the balance in the relic becomes sufficient.

### Recommendation

Do not add the profit to `toFree`, since the profit is already available as balance at hand:
```diff
- if (totalAssets > allocated) {
-     uint256 profit = totalAssets - allocated;
-     toFree += profit;
-     roi = int256(profit);
- } else if (totalAssets < allocated) {
-     roi = -int256(allocated - totalAssets);
- }
+ roi = int256(totalAssets) - int256(allocated)
```

### Cod3x-Labs
Acknowledged. If the issue is encountered, the team will deposit funds in the relic to undos 

### Cergyk
Acknowledged.

## L-1 ScdxUsdVaultStrategy::_liquidateAllPositions relic #1 can be burnt when emergencyWithdraw is called

### Description

ScdxUsdVaultStrategy has a migration strategy which liquidates all positions. The specific implementation resorts to first trying to use normal `Reliquary::withdraw` and then using `Reliquary::emergencyWithdraw`, if the former has failed. The problem lies in the fact that `Reliquary::emergencyWithdraw` automatically burns that relic, ignoring the special `status` of it.

[ScdxUsdVaultStrategy.sol#L148-L155](https://github.com/Cod3x-Labs/Cod3x-USD/blob/0346bab282ba646d0b431c16e7320a894eaf2361/contracts/staking_module/vault_strategy/ScdxUsdVaultStrategy.sol#L148-L155):
```solidity
    function _liquidateAllPositions() internal override returns (uint256) {
        try reliquary.withdraw(balanceOfPool(), RELIC_ID, address(this)) {}
        catch {
>>          reliquary.emergencyWithdraw(RELIC_ID);
        }

        return balanceOfWant();
    }
```

[Reliquary.sol#L375](https://github.com/Cod3x-Labs/Cod3x-USD/blob/0346bab282ba646d0b431c16e7320a894eaf2361/contracts/staking_module/reliquary/Reliquary.sol#L375):
```solidity
    function emergencyWithdraw(uint256 _relicId) external nonReentrant {
        address to_ = ownerOf(_relicId);
        if (to_ != msg.sender) revert Reliquary__NOT_OWNER();

        PositionInfo storage position = positionForId[_relicId];

        uint256 amount_ = uint256(position.amount);
        uint8 poolId_ = position.poolId;

        PoolInfo storage pool = poolInfo[poolId_];

        ReliquaryLogic._updatePool(pool, emissionRate, totalAllocPoint);

        pool.totalLpSupplied -= amount_ * pool.curve.getFunction(uint256(position.level));

>>      _burn(_relicId);
        delete positionForId[_relicId];

        ReliquaryRehypothecationLogic._withdraw(pool, amount_);

        IERC20(pool.poolToken).safeTransfer(to_, amount_);

        emit ReliquaryEvents.EmergencyWithdraw(poolId_, amount_, to_, _relicId);
    }
```

### Recommendation
Please consider adding a conditional around that burn statement:
```diff
    function emergencyWithdraw(uint256 _relicId) external nonReentrant {
        address to_ = ownerOf(_relicId);
        if (to_ != msg.sender) revert Reliquary__NOT_OWNER();

        PositionInfo storage position = positionForId[_relicId];

        uint256 amount_ = uint256(position.amount);
        uint8 poolId_ = position.poolId;

        PoolInfo storage pool = poolInfo[poolId_];

        ReliquaryLogic._updatePool(pool, emissionRate, totalAllocPoint);

        pool.totalLpSupplied -= amount_ * pool.curve.getFunction(uint256(position.level));

-       _burn(_relicId);
-       delete positionForId[_relicId];
+       if (_relicId != 1) {
+           _burn(_relicId);
+           delete positionForId[_relicId];
+       }
        ReliquaryRehypothecationLogic._withdraw(pool, amount_);

        IERC20(pool.poolToken).safeTransfer(to_, amount_);

        emit ReliquaryEvents.EmergencyWithdraw(poolId_, amount_, to_, _relicId);
    }
```

### Cod3x-Labs
Acknowledged. We think emergencyWithdraw(relic#1) and re-entering the position after may cause critical unexpected behavior since position reward accounting is not updated in emergencyWithdraw. (emergencyWithdraw is designed to burn the relic). So we will keep the code as it is. Considering that withdraw() fails, this means that there is a big problem with Reliquary, so emergencyWithdraw() is the only solution anyway.

### Cergyk
Acknowledged.

## L-2 Zap::zapOutStakedCdxUSD Zap out enables only imbalanced exit forcing users to pay balancer fee

### Description

When removing liquidity from a balancer pool, there is no fee if the user withdraws all of the tokens proportionally to the reserves of the pool. In the case where a user removes only of one token, a `virtual` swap is applied, and the equivalent balancer fee is charged.

The Zap contract used to interact with the CdxUSD staking module forces the user to withdraw only one token from the balancer pool, which means that the user will necessarily pay the Balancer pool fee.

### Recommendation
Enable the user to withdraw both of the tokens by using `ExitKind.EXACT_BPT_IN_FOR_TOKENS_OUT`

### Cod3x-Labs
Acknowledged.

### Cergyk
Acknowledged.

## L-3 ScdxUSDVaultStrategy should be able to handle ERC721

### Description

The ScdxUSDVaultStrategy receives the relic with id 1 and should be able to deposit and withdraw from it. If the `Cod3x-vault` owner decides to migrate to another strategy, it is currently impossible to do so, since no functions have been implemented to migrate the relic.

### Recommendation

Add a function `migrateRelic` which can transfer the relic with id 1 to the new strategy. Optionally implement the `IERC721Receiver` interface for `ScdxUSDVaultStrategy`, to mark it as capable to handle ERC721 tokens.

### Cod3x-Labs
Fixed in [f944da42](https://github.com/Cod3x-Labs/Cod3x-USD/commits/f944da42a1162dcfd5642d9ba31cb5d30e3c84b1)

### Cergyk
Fixed.

## L-4 Unsafe cast to uint256 in CdxUsdInterestRateStrategy::transferFunction

### Description

The cast to uint256 in `transferFunction` is unsafe, and could be triggered if the `controllerError` is either `< 0` or `> RAY`. In that case the resulting uint256 value will be close to the maximum, and cause an overflow in the interest accrual logic.

This is info severity, because in the current interest rate model `_minControllerError` should be `>= 0` to disable negative interest rates, and the accumulated error can only become `> RAY` after an enormous duration of imbalance (long after the interest rates have been raised to absurd levels)

### Recommendation
Ensure that `_minControllerError` is >= 0, so that `ce` is always >= in `transferFunction`

### Cod3x-Labs
Fixed in [c668e534](https://github.com/Cod3x-Labs/Cod3x-USD/commits/c668e5348ec0fb56fd6733bac02ec78f9ffae476)

### Cergyk
Fixed.

## Informational & Gas issues

### INFO-1 transferFunction positivity check is useless given signature

The following positivity checks on `transferFunction` are useless, since it returns a uint256:

[CdxUsdIInterestRateStrategy.sol#L189](https://github.com/Cod3x-Labs/Cod3x-USD/blob/0346bab282ba646d0b431c16e7320a894eaf2361/contracts/facilitators/cod3x_lend/interest_strategy/CdxUsdIInterestRateStrategy.sol#L189)
```solidity
if (transferFunction(type(int256).min) < 0) {
    revert PiReserveInterestRateStrategy__BASE_BORROW_RATE_CANT_BE_NEGATIVE();
}
```

[CdxUsdIInterestRateStrategy.sol#L137-L139](https://github.com/Cod3x-Labs/Cod3x-USD/blob/0346bab282ba646d0b431c16e7320a894eaf2361/contracts/facilitators/cod3x_lend/interest_strategy/CdxUsdIInterestRateStrategy.sol#L137-L139)
```solidity
if (transferFunction(type(int256).min) < 0) {
    revert PiReserveInterestRateStrategy__BASE_BORROW_RATE_CANT_BE_NEGATIVE();
}
```

Additionally the cast [CdxUsdIInterestRateStrategy.sol#L328](https://github.com/Cod3x-Labs/Cod3x-USD/blob/0346bab282ba646d0b431c16e7320a894eaf2361/contracts/facilitators/cod3x_lend/interest_strategy/CdxUsdIInterestRateStrategy.sol#L328) is useless:
```solidity
function baseVariableBorrowRate() public view override returns (uint256) {
    return uint256(transferFunction(type(int256).min));
}
```

#### Cod3x-Labs
Fixed in [15d693ae](https://github.com/Cod3x-Labs/Cod3x-USD/commits/15d693aeac9022a6d7eac7d1e2f9839d924174d5)

#### Cergyk
Fixed.

### INFO-2 Setters do not emit events in CdxUsdInterestRateStrategy

The following setters available in `CdxUsdInterestRateStrategy` do not emit an event, which will hinder observability of config changes:
- setMinControllerError
- setPidValues
- setOracleValues
- setBalancerPoolId
- setManualInterestRate
- setErrI

Same for the following setters in `CdxUsdAToken`:
- setVariableDebtToken
- setReliquaryInfo
- setIncentivesController
- setTreasury

Would recommend a consistent handling of setters events accross all files.

#### Cod3x-Labs
Fixed in [8894e7f1](https://github.com/Cod3x-Labs/Cod3x-USD/commits/8894e7f1a3ce5391dcaf8d5396d9f0ea8b1c8c02)

#### Cergyk
Fixed.

### INFO-3 _maxErrIAmp is redundant with _minControllerError

The parameter `_maxErrIAmp` is now redundant with `_minControllerError`, these two parameter check that the error during an interest rate update is above a given value.

#### Cod3x-Labs
Fixed in [15d693ae](https://github.com/Cod3x-Labs/Cod3x-USD/commits/15d693aeac9022a6d7eac7d1e2f9839d924174d5)

#### Cergyk
Fixed.

### INFO-4 OFTExtended hourly rate limit allows for 2\*eidToConfigPtr.hourlyLimit in a 2\*hour window

The rate limiting mechanism is slightly flawed, because instead of limiting during a 1 hour window as suggested, it limits over a 2 hour window (the limit is correct though).

#### Cod3x-Labs
Acknowledged.

#### Cergyk
Acknowledged.


### INFO-5 Initialization flow of CdxUSDAToken can be simplified

Setters setVariableDebtToken(), updateCdxUsdTreasury(), setReliquaryInfo(), should be included in the `initialize()` to avoid admin mistakes during initialization

#### Cod3x-Labs
Fixed in [15d693ae](https://github.com/Cod3x-Labs/Cod3x-USD/commits/15d693aeac9022a6d7eac7d1e2f9839d924174d5)

#### Cergyk
Fixed.

### INFO-6 OFTExtended::_debit xChain transfers can fail due to wrong fee take

Replace `msg.sender` with `_from` in `OFTExtended::_debit`, in case `sendFrom`

[OFTExtended.sol#L202](https://github.com/Cod3x-Labs/Cod3x-USD/blob/0346bab282ba646d0b431c16e7320a894eaf2361/contracts/tokens/OFTExtended.sol#L202):
```diff
    // Send fee to treasury
    uint256 feeAmt_ = amountSentLD_ - amountReceivedLD_;
    if (feeAmt_ != 0) {
-        _transfer(msg.sender, treasury, feeAmt_);
+        _transfer(_from, treasury, feeAmt_);
    }
```

#### Cod3x-Labs
Fixed in [15d693ae](https://github.com/Cod3x-Labs/Cod3x-USD/commits/15d693aeac9022a6d7eac7d1e2f9839d924174d5)

#### Cergyk
Fixed.

### INFO-7 typos and unaccurate comments

- `Zap::zapOutRelic`: `Bpt` instead of `Btp`
- `BalancerHelper`: `bptIndex_` instead of `btpIndex_`
- `CdxUsdIInterestRateStrategy::transferFunction`: comment refers to wrong desmos link
- [Zap.sol#L339](https://github.com/Cod3x-Labs/Cod3x-USD/blob/0346bab282ba646d0b431c16e7320a894eaf2361/contracts/staking_module/Zap.sol#L339): should read `/// Send token`.

#### Cod3x-Labs
Fixed in [15d693ae](https://github.com/Cod3x-Labs/Cod3x-USD/commits/15d693aeac9022a6d7eac7d1e2f9839d924174d5)

#### Cergyk
Fixed.

