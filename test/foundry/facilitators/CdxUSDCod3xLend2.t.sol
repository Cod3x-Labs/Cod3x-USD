// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

// Cod3x Lend
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ERC20} from "lib/Cod3x-Lend/contracts/dependencies/openzeppelin/contracts/ERC20.sol";
import "lib/Cod3x-Lend/contracts/protocol/libraries/helpers/Errors.sol";
import "lib/Cod3x-Lend/contracts/protocol/libraries/types/DataTypes.sol";
import {AToken} from "lib/Cod3x-Lend/contracts/protocol/tokenization/AToken.sol";
import {VariableDebtToken} from
    "lib/Cod3x-Lend/contracts/protocol/tokenization/VariableDebtToken.sol";

import {WadRayMath} from "lib/Cod3x-Lend/contracts/protocol/libraries/math/WadRayMath.sol";
import {MathUtils} from "lib/Cod3x-Lend/contracts/protocol/libraries/math/MathUtils.sol";
// import {ReserveBorrowConfiguration} from  "lib/Cod3x-Lend/contracts/protocol/libraries/configuration/ReserveConfiguration.sol";

// Balancer
import {
    IVault,
    JoinKind,
    ExitKind,
    SwapKind
} from "contracts/staking_module/vault_strategy/interfaces/IVault.sol";
import {
    IComposableStablePoolFactory,
    IRateProvider,
    ComposableStablePool
} from "contracts/staking_module/vault_strategy/interfaces/IComposableStablePoolFactory.sol";
import "forge-std/console.sol";

import {TestCdxUSDAndLendAndStaking} from "test/helpers/TestCdxUSDAndLendAndStaking.sol";
import {ERC20Mock} from "../../helpers/mocks/ERC20Mock.sol";

// reliquary
import "contracts/staking_module/reliquary/Reliquary.sol";
import "contracts/staking_module/reliquary/interfaces/IReliquary.sol";
import "contracts/staking_module/reliquary/nft_descriptors/NFTDescriptor.sol";
import "contracts/staking_module/reliquary/curves/LinearPlateauCurve.sol";
import "contracts/staking_module/reliquary/rewarders/RollingRewarder.sol";
import "contracts/staking_module/reliquary/rewarders/ParentRollingRewarder.sol";
import "contracts/staking_module/reliquary/interfaces/ICurves.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

// vault
import {ReaperBaseStrategyv4} from "lib/Cod3x-Vault/src/ReaperBaseStrategyv4.sol";
import {ReaperVaultV2} from "lib/Cod3x-Vault/src/ReaperVaultV2.sol";
import {ScdxUsdVaultStrategy} from
    "contracts/staking_module/vault_strategy/ScdxUsdVaultStrategy.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "lib/Cod3x-Vault/test/vault/mock/FeeControllerMock.sol";
import "contracts/staking_module/vault_strategy/libraries/BalancerHelper.sol";

// CdxUSD
import {CdxUSD} from "contracts/tokens/CdxUSD.sol";
import {CdxUsdIInterestRateStrategy} from
    "contracts/facilitators/cod3x_lend/interest_strategy/CdxUsdIInterestRateStrategy.sol";
import {CdxUsdOracle} from "contracts/facilitators/cod3x_lend/oracle/CdxUsdOracle.sol";
import {CdxUsdAToken} from "contracts/facilitators/cod3x_lend/token/CdxUsdAToken.sol";
import {CdxUsdVariableDebtToken} from
    "contracts/facilitators/cod3x_lend/token/CdxUsdVariableDebtToken.sol";
import {MockV3Aggregator} from "test/helpers/mocks/MockV3Aggregator.sol";

/// events
event Deposit(address indexed reserve, address user, address indexed onBehalfOf, uint256 amount);

event Withdraw(address indexed reserve, address indexed user, address indexed to, uint256 amount);

event Borrow(
    address indexed reserve,
    address user,
    address indexed onBehalfOf,
    uint256 amount,
    uint256 borrowRate
);

event Repay(address indexed reserve, address indexed user, address indexed repayer, uint256 amount);

contract TestCdxUSDCod3xLend2 is TestCdxUSDAndLendAndStaking {
    using WadRayMath for uint256;

    // classical deposit/withdraw without cdxUSD
    function testDepositsAndWithdrawals(uint256 amount) public {
        address user = makeAddr("user");

        for (uint32 idx = 0; idx < aTokens.length - 1; idx++) {
            uint256 _userGrainBalanceBefore = aTokens[idx].balanceOf(address(user));
            uint256 _thisBalanceTokenBefore = erc20Tokens[idx].balanceOf(address(this));
            amount = bound(amount, 10_000, erc20Tokens[idx].balanceOf(address(this)));

            /* Deposit on behalf of user */
            erc20Tokens[idx].approve(address(deployedContracts.lendingPool), amount);
            vm.expectEmit(true, true, true, true);
            emit Deposit(address(erc20Tokens[idx]), address(this), user, amount);
            deployedContracts.lendingPool.deposit(address(erc20Tokens[idx]), true, amount, user);
            assertEq(_thisBalanceTokenBefore, erc20Tokens[idx].balanceOf(address(this)) + amount);
            assertEq(_userGrainBalanceBefore + amount, aTokens[idx].balanceOf(address(user)));

            /* User shall be able to withdraw underlying tokens */
            vm.startPrank(user);
            vm.expectEmit(true, true, true, true);
            emit Withdraw(address(erc20Tokens[idx]), user, user, amount);
            deployedContracts.lendingPool.withdraw(address(erc20Tokens[idx]), true, amount, user);
            vm.stopPrank();
            assertEq(amount, erc20Tokens[idx].balanceOf(user));
            assertEq(_userGrainBalanceBefore, aTokens[idx].balanceOf(address(this)));
        }
    }

    function testDaiBorrow() public {
        address user = makeAddr("user");
        uint256 amount = 1e18;

        uint256 _userAWethBalanceBefore = aTokens[1].balanceOf(address(user));
        uint256 _thisWethBalanceBefore = erc20Tokens[1].balanceOf(address(this));

        // Deposit weth on behalf of user
        erc20Tokens[1].approve(address(deployedContracts.lendingPool), amount);
        vm.expectEmit(true, true, true, true);
        emit Deposit(address(erc20Tokens[1]), address(this), user, amount);
        deployedContracts.lendingPool.deposit(address(erc20Tokens[1]), true, amount, user);

        assertEq(_thisWethBalanceBefore, erc20Tokens[1].balanceOf(address(this)) + amount);
        assertEq(_userAWethBalanceBefore + amount, aTokens[1].balanceOf(address(user)));

        // Deposit dai on behalf of user
        erc20Tokens[2].approve(address(deployedContracts.lendingPool), type(uint256).max);
        deployedContracts.lendingPool.deposit(address(erc20Tokens[2]), true, 10000e18, user);

        // Borrow/Mint cdxUSD
        uint256 amountMintDai = 1000e18;
        vm.startPrank(user);
        deployedContracts.lendingPool.borrow(address(erc20Tokens[2]), true, amountMintDai, user);
        uint256 balanceUserBefore = erc20Tokens[2].balanceOf(user);
        assertEq(amountMintDai, balanceUserBefore);
        (uint256 totalCollateralETH, uint256 totalDebtETH,,,, uint256 healthFactor1) =
            deployedContracts.lendingPool.getUserAccountData(user);
        console.log("totalCollateralETH = ", totalCollateralETH);
        console.log("totalDebtETH = ", totalDebtETH);
        console.log("getReservesCount = ", deployedContracts.lendingPool.getReservesCount());

        vm.startPrank(user);
        erc20Tokens[2].approve(address(deployedContracts.lendingPool), type(uint256).max);
        deployedContracts.lendingPool.repay(address(erc20Tokens[2]), true, amountMintDai / 2, user);
        (,,,,, uint256 healthFactor2) = deployedContracts.lendingPool.getUserAccountData(user);
        assertGt(healthFactor2, healthFactor1);
        assertGt(balanceUserBefore, cdxUsd.balanceOf(user));
    }

    function testCdxUsdBorrow() public {
        address user = makeAddr("user");
        uint256 amount = 1e18;

        uint256 _userAWethBalanceBefore = aTokens[1].balanceOf(address(user));
        uint256 _thisWethBalanceBefore = erc20Tokens[1].balanceOf(address(this));

        // Deposit weth on behalf of user
        erc20Tokens[1].approve(address(deployedContracts.lendingPool), amount);
        vm.expectEmit(true, true, true, true);
        emit Deposit(address(erc20Tokens[1]), address(this), user, amount);
        deployedContracts.lendingPool.deposit(address(erc20Tokens[1]), true, amount, user);

        assertEq(_thisWethBalanceBefore, erc20Tokens[1].balanceOf(address(this)) + amount);
        assertEq(_userAWethBalanceBefore + amount, aTokens[1].balanceOf(address(user)));

        // Borrow/Mint cdxUSD
        uint256 amountMintCdxUsd = 1000e18;
        vm.startPrank(user);
        deployedContracts.lendingPool.borrow(address(cdxUsd), true, amountMintCdxUsd, user);
        uint256 balanceUserBefore = cdxUsd.balanceOf(user);
        assertEq(amountMintCdxUsd, balanceUserBefore);
        (uint256 totalCollateralETH, uint256 totalDebtETH,,,, uint256 healthFactor1) =
            deployedContracts.lendingPool.getUserAccountData(user);

        vm.startPrank(user);
        cdxUsd.approve(address(deployedContracts.lendingPool), type(uint256).max);
        deployedContracts.lendingPool.repay(address(cdxUsd), true, amountMintCdxUsd / 2, user);
        (,,,,, uint256 healthFactor2) = deployedContracts.lendingPool.getUserAccountData(user);
        assertGt(healthFactor2, healthFactor1);
        assertGt(balanceUserBefore, cdxUsd.balanceOf(user));
    }

    function testBorrowRepay() public {
        address user = makeAddr("user");

        ERC20 dai = erc20Tokens[2];
        ERC20 wbtc = erc20Tokens[1];
        uint256 daiDepositAmount = 5000e18; /* $5k */ // consider fuzzing here

        uint256 wbtcPrice = oracle.getAssetPrice(address(wbtc));
        uint256 daiPrice = oracle.getAssetPrice(address(dai));
        uint256 daiDepositValue = daiDepositAmount * daiPrice / (10 ** PRICE_FEED_DECIMALS);
        (, uint256 daiLtv,,,,,,,) =
            deployedContracts.protocolDataProvider.getReserveConfigurationData(address(dai), true);
        uint256 wbtcMaxBorrowAmountWithDaiCollateral;
        {
            uint256 daiMaxBorrowValue = daiLtv * daiDepositValue / 10_000;

            uint256 wbtcMaxBorrowAmountRay = daiMaxBorrowValue.rayDiv(wbtcPrice);
            wbtcMaxBorrowAmountWithDaiCollateral = fixture_preciseConvertWithDecimals(
                wbtcMaxBorrowAmountRay, dai.decimals(), wbtc.decimals()
            );
            // (daiMaxBorrowValue * 10 ** PRICE_FEED_DECIMALS) / wbtcPrice;
        }
        require(
            wbtc.balanceOf(address(this)) > wbtcMaxBorrowAmountWithDaiCollateral, "Too less wbtc"
        );
        uint256 wbtcDepositAmount = wbtcMaxBorrowAmountWithDaiCollateral * 15 / 10;

        /* Main user deposits Dai and wants to borrow */
        dai.approve(address(deployedContracts.lendingPool), daiDepositAmount);
        deployedContracts.lendingPool.deposit(address(dai), true, daiDepositAmount, address(this));

        /* Other user deposits wbtc thanks to that there is enough funds to borrow */
        wbtc.approve(address(deployedContracts.lendingPool), wbtcDepositAmount);
        deployedContracts.lendingPool.deposit(address(wbtc), true, wbtcDepositAmount, user);

        uint256 wbtcBalanceBeforeBorrow = wbtc.balanceOf(address(this));

        (,,,, uint256 reserveFactors,,,,) =
            deployedContracts.protocolDataProvider.getReserveConfigurationData(address(wbtc), true);
        (, uint256 expectedBorrowRate) = deployedContracts.volatileStrategy.calculateInterestRates(
            address(wbtc),
            address(aTokens[1]),
            0,
            wbtcMaxBorrowAmountWithDaiCollateral,
            wbtcMaxBorrowAmountWithDaiCollateral,
            reserveFactors
        );

        /* Main user borrows maxPossible amount of wbtc */
        vm.expectEmit(true, true, true, true);
        emit Borrow(
            address(wbtc),
            address(this),
            address(this),
            wbtcMaxBorrowAmountWithDaiCollateral,
            expectedBorrowRate
        );
        deployedContracts.lendingPool.borrow(
            address(wbtc), true, wbtcMaxBorrowAmountWithDaiCollateral, address(this)
        );
        /* Main user's balance should be: initial amount + borrowed amount */
        assertEq(
            wbtcBalanceBeforeBorrow + wbtcMaxBorrowAmountWithDaiCollateral,
            wbtc.balanceOf(address(this))
        );

        /* Main user repays his debt */
        wbtc.approve(address(deployedContracts.lendingPool), wbtcMaxBorrowAmountWithDaiCollateral);
        vm.expectEmit(true, true, true, true);
        emit Repay(
            address(wbtc), address(this), address(this), wbtcMaxBorrowAmountWithDaiCollateral
        );
        deployedContracts.lendingPool.repay(
            address(wbtc), true, wbtcMaxBorrowAmountWithDaiCollateral, address(this)
        );
        /* Main user's balance should be the same as before borrowing */
        assertEq(wbtcBalanceBeforeBorrow, wbtc.balanceOf(address(this)));
    }
}
