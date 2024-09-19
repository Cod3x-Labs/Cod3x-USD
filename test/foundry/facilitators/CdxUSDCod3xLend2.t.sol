// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

// Cod3x Lend
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ERC20} from "lib/Cod3x-Lend/contracts/dependencies/openzeppelin/contracts/ERC20.sol";
import "lib/Cod3x-Lend/contracts/protocol/libraries/helpers/Errors.sol";
import "lib/Cod3x-Lend/contracts/protocol/libraries/types/DataTypes.sol";
import {AToken} from "lib/Cod3x-Lend/contracts/protocol/tokenization/ERC20/AToken.sol";
import {VariableDebtToken} from
    "lib/Cod3x-Lend/contracts/protocol/tokenization/ERC20/VariableDebtToken.sol";

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
import {CdxUsdOracle} from "contracts/facilitators/cod3x_lend/oracle/CdxUSDOracle.sol";
import {CdxUsdAToken} from "contracts/facilitators/cod3x_lend/token/CdxUsdAToken.sol";
import {CdxUsdVariableDebtToken} from
    "contracts/facilitators/cod3x_lend/token/CdxUsdVariableDebtToken.sol";
import {MockV3Aggregator} from "test/helpers/mocks/MockV3Aggregator.sol";
import {ILendingPool} from "lib/Cod3x-Lend/contracts/interfaces/ILendingPool.sol";

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

    uint256 NR_OF_ASSETS = 3;

    address notApproved = makeAddr("NotApproved");

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

    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external returns (bool) {
        uint256[] memory totalAmountsToPay = new uint256[](assets.length);
        (uint256[] memory balancesBefore, address sender) = abi.decode(params, (uint256[], address)); //uint256[], address
        if ((sender == address(this))) {
            for (uint32 idx = 0; idx < assets.length; idx++) {
                console.log("[In] Premium: ", premiums[idx]);
                console.log("Balance: ", IERC20(assets[idx]).balanceOf(sender));
                totalAmountsToPay[idx] = amounts[idx] + premiums[idx];
                assertEq(balancesBefore[idx] + amounts[idx], IERC20(assets[idx]).balanceOf(sender));
                assertEq(assets[idx], tokens[idx]);
                IERC20(assets[idx]).approve(
                    address(deployedContracts.lendingPool), totalAmountsToPay[idx]
                );
            }
            assertEq(sender, address(this));
            return true;
        } else if (sender == notApproved) {
            for (uint32 idx = 0; idx < assets.length; idx++) {
                console.log("[In] Premium: ", premiums[idx]);
                totalAmountsToPay[idx] = amounts[idx] + premiums[idx];
                assertEq(
                    balancesBefore[idx] + amounts[idx], IERC20(assets[idx]).balanceOf(address(this))
                );
                assertEq(assets[idx], tokens[idx]);
            }
            return true;
        } else {
            return false;
        }
    }

    // TODO fix FL on cod3x lend
    function testFlasloanCdxUsd() public {
        address user = makeAddr("user");
        uint256 amount = 1000e18;

        // supply cdxUSD

        /* Deposit on behalf of user */
        erc20Tokens[0].approve(address(deployedContracts.lendingPool), 1e8);
        deployedContracts.lendingPool.deposit(address(erc20Tokens[0]), true, 1e8, user);

        /* User shall be able to withdraw underlying tokens */
        vm.startPrank(user);
        deployedContracts.lendingPool.borrow(address(erc20Tokens[3]), true, amount, user);
        vm.stopPrank();

        // Flashloan
        bool[] memory reserveTypes = new bool[](1);
        address[] memory tokenAddresses = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        uint256[] memory modes = new uint256[](1);
        uint256[] memory balancesBefore = new uint256[](1);

        reserveTypes[0] = true;
        tokenAddresses[0] = address(cdxUsd);
        amounts[0] = 1e18;
        modes[0] = 0;
        balancesBefore[0] = cdxUsd.balanceOf(address(this));

        ILendingPool.FlashLoanParams memory flashloanParams =
            ILendingPool.FlashLoanParams(address(this), tokenAddresses, reserveTypes, address(this));
        bytes memory params = abi.encode(balancesBefore, address(this));

        // vm.expectRevert();
        ILendingPool(address(deployedContracts.lendingPool)).flashLoan(
            flashloanParams, amounts, modes, params
        );
    }

    function testLiquidationOfCdxUsd(uint256 priceDecrease, uint256 idx) public {
        idx = bound(idx, 0, 2);
        ERC20 wbtc = ERC20(erc20Tokens[idx]);
        ERC20 cdxUsd = ERC20(erc20Tokens[3]);

        uint256 cdxUsdPrice = oracle.getAssetPrice(address(cdxUsd));
        uint256 wbtcPrice = oracle.getAssetPrice(address(wbtc));
        {
            uint256 wbtcDepositAmount = 10 ** wbtc.decimals();
            (, uint256 wbtcLtv,,,,,,,) = deployedContracts
                .protocolDataProvider
                .getReserveConfigurationData(address(wbtc), true);

            uint256 wbtcMaxBorrowAmount = wbtcLtv * wbtcDepositAmount / 10_000;
            uint256 cdxUsdMaxBorrowAmountWithWbtcCollateral = (
                (wbtcMaxBorrowAmount * wbtcPrice * 10 ** (cdxUsd.decimals() - wbtc.decimals()))
                    / (10 ** PRICE_FEED_DECIMALS)
            );
            require(
                cdxUsd.balanceOf(address(this)) > cdxUsdMaxBorrowAmountWithWbtcCollateral,
                "Too less cdxUsd"
            );

            /* Main user deposits usdc and wants to borrow */
            wbtc.approve(address(deployedContracts.lendingPool), wbtcDepositAmount);
            deployedContracts.lendingPool.deposit(
                address(wbtc), true, wbtcDepositAmount, address(this)
            );
            /* Main user borrows maxPossible amount of cdxUsd */
            deployedContracts.lendingPool.borrow(
                address(cdxUsd), true, cdxUsdMaxBorrowAmountWithWbtcCollateral, address(this)
            );
        }
        {
            (,,,,, uint256 healthFactor) =
                deployedContracts.lendingPool.getUserAccountData(address(this));
            assertGe(healthFactor, 1 ether);
            // console.log("Health factor: ", healthFactor);
        }

        /* simulate btc price increase */
        {
            priceDecrease = bound(priceDecrease, 800, 1000); // 8-12%
            int256[] memory prices = new int256[](4);
            prices[0] = int256(oracle.getAssetPrice(address(wbtc)));
            prices[1] = int256(oracle.getAssetPrice(address(weth)));
            prices[2] = int256(oracle.getAssetPrice(address(dai)));

            uint256 newPrice = (wbtcPrice - wbtcPrice * priceDecrease / 10_000);
            prices[idx] = int256(newPrice);
            prices[3] = int256(cdxUsdPrice);

            address[] memory aggregators = new address[](4);
            (, aggregators) = fixture_getTokenPriceFeeds(erc20Tokens, prices);

            oracle.setAssetSources(tokens, aggregators);
            cdxUsdPrice = newPrice;
        }

        ReserveDataParams memory cdxUsdReserveParamsBefore =
            fixture_getReserveData(address(cdxUsd), deployedContracts.protocolDataProvider);
        ReserveDataParams memory wbtcReserveParamsBefore =
            fixture_getReserveData(address(wbtc), deployedContracts.protocolDataProvider);
        {
            (,,,,, uint256 healthFactor) =
                deployedContracts.lendingPool.getUserAccountData(address(this));
            assertLt(healthFactor, 1 ether, "Health factor greater or equal than 1");
            console.log("healthFactor: ", healthFactor);
        }
        /**
         * LIQUIDATION PROCESS - START ***********
         */
        uint256 amountToLiquidate;
        uint256 scaledVariableDebt;
        {
            (, uint256 debtToCover, uint256 _scaledVariableDebt,,) = deployedContracts
                .protocolDataProvider
                .getUserReserveData(address(cdxUsd), true, address(this));
            amountToLiquidate = debtToCover / 2; // maximum possible liquidation amount
            scaledVariableDebt = _scaledVariableDebt;
        }
        {
            /* prepare funds */
            address liquidator = makeAddr("liquidator");
            cdxUsd.transfer(liquidator, amountToLiquidate);

            vm.startPrank(liquidator);
            cdxUsd.approve(address(deployedContracts.lendingPool), amountToLiquidate);
            deployedContracts.lendingPool.liquidationCall(
                address(wbtc), true, address(cdxUsd), true, address(this), amountToLiquidate, false
            );
            vm.stopPrank();
        }
        /**
         * LIQUIDATION PROCESS - END ***********
         */
        ReserveDataParams memory cdxUsdReserveParamsAfter =
            fixture_getReserveData(address(cdxUsd), deployedContracts.protocolDataProvider);
        ReserveDataParams memory wbtcReserveParamsAfter =
            fixture_getReserveData(address(wbtc), deployedContracts.protocolDataProvider);
        uint256 expectedCollateralLiquidated;

        {
            (,,, uint256 liquidationBonus,,,,,) = deployedContracts
                .protocolDataProvider
                .getReserveConfigurationData(address(wbtc), true);

            expectedCollateralLiquidated = cdxUsdPrice
                * (amountToLiquidate * liquidationBonus / 10_000) * 10 ** wbtc.decimals()
                / (wbtcPrice * 10 ** cdxUsd.decimals());
        }
        uint256 variableDebtBeforeTx = fixture_calcExpectedVariableDebtTokenBalance(
            cdxUsdReserveParamsBefore.variableBorrowRate,
            cdxUsdReserveParamsBefore.variableBorrowIndex,
            cdxUsdReserveParamsBefore.lastUpdateTimestamp,
            scaledVariableDebt,
            block.timestamp
        );
        {
            (,,,,, uint256 healthFactor) =
                deployedContracts.lendingPool.getUserAccountData(address(this));
            console.log("healthFactor AFTER: ", healthFactor);
            assertGt(healthFactor, 1 ether);
        }

        (, uint256 currentVariableDebt,,,) = deployedContracts
            .protocolDataProvider
            .getUserReserveData(address(cdxUsd), true, address(this));

        assertApproxEqRel(
            currentVariableDebt,
            variableDebtBeforeTx - amountToLiquidate,
            0.01e18,
            "Debt not accurate"
        );
        assertApproxEqRel(
            cdxUsdReserveParamsAfter.availableLiquidity,
            cdxUsdReserveParamsBefore.availableLiquidity + amountToLiquidate,
            0.01e18,
            "Available liquidity not accurate"
        );
        assertGe(
            cdxUsdReserveParamsAfter.liquidityIndex,
            cdxUsdReserveParamsBefore.liquidityIndex,
            "Liquidity Index Less than before"
        );
        // assertLt(
        //     cdxUsdReserveParamsAfter.liquidityRate,
        //     cdxUsdReserveParamsBefore.liquidityRate,
        //     "Liquidity rate greater or equal than before"
        // );
        // assertApproxEqRel(
        //     wbtcReserveParamsAfter.availableLiquidity,
        //     wbtcReserveParamsBefore.availableLiquidity - expectedCollateralLiquidated,
        //     0.01e18,
        //     "Available liquidity after liquidation not accurate"
        // );
        {
            (,,,, bool usageAsCollateralEnabled) = deployedContracts
                .protocolDataProvider
                .getUserReserveData(address(wbtc), true, address(this));
            assertEq(usageAsCollateralEnabled, true, "Usage as collaterall disabled");
        }
    }

    function testLiquidationReceiveUnderlying(uint256 priceIncrease) public {
        ERC20 dai = ERC20(erc20Tokens[2]);
        ERC20 wbtc = ERC20(erc20Tokens[0]);

        uint256 wbtcPrice = oracle.getAssetPrice(address(wbtc));
        uint256 daiPrice = oracle.getAssetPrice(address(dai));
        {
            uint256 daiDepositAmount = 5e21; /* $5k */ // consider fuzzing here
            (, uint256 daiLtv,,,,,,,) = deployedContracts
                .protocolDataProvider
                .getReserveConfigurationData(address(dai), true);

            uint256 daiMaxBorrowAmount = daiLtv * daiDepositAmount / 10_000;

            uint256 wbtcMaxToBorrowRay = daiMaxBorrowAmount.rayDiv(wbtcPrice);
            uint256 wbtcMaxBorrowAmountWithDaiCollateral = fixture_preciseConvertWithDecimals(
                wbtcMaxToBorrowRay, dai.decimals(), wbtc.decimals()
            );
            require(
                wbtc.balanceOf(address(this)) > wbtcMaxBorrowAmountWithDaiCollateral,
                "Too less wbtc"
            );
            uint256 wbtcDepositAmount = wbtc.balanceOf(address(this)) / 2;

            /* Main user deposits usdc and wants to borrow */
            dai.approve(address(deployedContracts.lendingPool), daiDepositAmount);
            deployedContracts.lendingPool.deposit(
                address(dai), true, daiDepositAmount, address(this)
            );

            /* Other user deposits wbtc thanks to that there is enough funds to borrow */
            {
                address user = makeAddr("user");
                wbtc.approve(address(deployedContracts.lendingPool), wbtcDepositAmount);
                deployedContracts.lendingPool.deposit(address(wbtc), true, wbtcDepositAmount, user);
            }
            /* Main user borrows maxPossible amount of wbtc */
            deployedContracts.lendingPool.borrow(
                address(wbtc), true, wbtcMaxBorrowAmountWithDaiCollateral, address(this)
            );
        }
        {
            (,,,,, uint256 healthFactor) =
                deployedContracts.lendingPool.getUserAccountData(address(this));
            assertGe(healthFactor, 1 ether);
        }

        /* simulate btc price increase */
        {
            priceIncrease = bound(priceIncrease, 800, 1_200); // 8-12%
            uint256 newPrice = (wbtcPrice + wbtcPrice * priceIncrease / 10_000);
            int256[] memory prices = new int256[](4);
            prices[0] = int256(newPrice);
            prices[1] = int256(oracle.getAssetPrice(address(weth)));
            prices[2] = int256(oracle.getAssetPrice(address(dai)));
            prices[3] = int256(oracle.getAssetPrice(address(cdxUsd)));
            address[] memory aggregators = new address[](4);
            (, aggregators) = fixture_getTokenPriceFeeds(erc20Tokens, prices);

            oracle.setAssetSources(tokens, aggregators);
            wbtcPrice = newPrice;
        }

        ReserveDataParams memory wbtcReserveParamsBefore =
            fixture_getReserveData(address(wbtc), deployedContracts.protocolDataProvider);
        ReserveDataParams memory daiReserveParamsBefore =
            fixture_getReserveData(address(dai), deployedContracts.protocolDataProvider);
        {
            (,,,,, uint256 healthFactor) =
                deployedContracts.lendingPool.getUserAccountData(address(this));
            assertLt(healthFactor, 1 ether, "Health factor greater or equal than 1");
            // console.log("healthFactor: ", healthFactor);
        }

        /**
         * LIQUIDATION PROCESS - START ***********
         */
        uint256 amountToLiquidate;
        uint256 scaledVariableDebt;
        {
            (, uint256 debtToCover, uint256 _scaledVariableDebt,,) = deployedContracts
                .protocolDataProvider
                .getUserReserveData(address(wbtc), true, address(this));
            amountToLiquidate = debtToCover / 2; // maximum possible liquidation amount
            scaledVariableDebt = _scaledVariableDebt;
        }
        {
            /* prepare funds */
            address liquidator = makeAddr("liquidator");
            wbtc.transfer(liquidator, amountToLiquidate);

            vm.startPrank(liquidator);
            wbtc.approve(address(deployedContracts.lendingPool), amountToLiquidate);
            deployedContracts.lendingPool.liquidationCall(
                address(dai), true, address(wbtc), true, address(this), amountToLiquidate, false
            );
            vm.stopPrank();
        }
        /**
         * LIQUIDATION PROCESS - END ***********
         */
        ReserveDataParams memory wbtcReserveParamsAfter =
            fixture_getReserveData(address(wbtc), deployedContracts.protocolDataProvider);
        ReserveDataParams memory daiReserveParamsAfter =
            fixture_getReserveData(address(dai), deployedContracts.protocolDataProvider);
        uint256 expectedCollateralLiquidated;

        {
            (,,, uint256 liquidationBonus,,,,,) = deployedContracts
                .protocolDataProvider
                .getReserveConfigurationData(address(dai), true);

            expectedCollateralLiquidated = wbtcPrice
                * (amountToLiquidate * liquidationBonus / 10_000) * 10 ** dai.decimals()
                / (daiPrice * 10 ** wbtc.decimals());
        }
        uint256 variableDebtBeforeTx = fixture_calcExpectedVariableDebtTokenBalance(
            wbtcReserveParamsBefore.variableBorrowRate,
            wbtcReserveParamsBefore.variableBorrowIndex,
            wbtcReserveParamsBefore.lastUpdateTimestamp,
            scaledVariableDebt,
            block.timestamp
        );
        {
            (,,,,, uint256 healthFactor) =
                deployedContracts.lendingPool.getUserAccountData(address(this));
            // console.log("AFTER LIQUIDATION: ");
            // console.log("healthFactor: ", healthFactor);
            assertGt(healthFactor, 1 ether);
        }

        (, uint256 currentVariableDebt,,,) = deployedContracts
            .protocolDataProvider
            .getUserReserveData(address(wbtc), true, address(this));

        assertApproxEqRel(currentVariableDebt, variableDebtBeforeTx - amountToLiquidate, 0.01e18);
        assertApproxEqRel(
            wbtcReserveParamsAfter.availableLiquidity,
            wbtcReserveParamsBefore.availableLiquidity + amountToLiquidate,
            0.01e18
        );
        assertGe(wbtcReserveParamsAfter.liquidityIndex, wbtcReserveParamsBefore.liquidityIndex);
        assertLt(wbtcReserveParamsAfter.liquidityRate, wbtcReserveParamsBefore.liquidityRate);
        assertApproxEqRel(
            daiReserveParamsAfter.availableLiquidity,
            daiReserveParamsBefore.availableLiquidity - expectedCollateralLiquidated,
            0.01e18
        );
        {
            (,,,, bool usageAsCollateralEnabled) = deployedContracts
                .protocolDataProvider
                .getUserReserveData(address(dai), true, address(this));
            assertEq(usageAsCollateralEnabled, true);
        }
    }

    function testLiquidationReceiveAToken(uint256 priceIncrease) public {
        ERC20 dai = ERC20(erc20Tokens[2]);
        ERC20 wbtc = ERC20(erc20Tokens[0]);

        uint256 wbtcPrice = oracle.getAssetPrice(address(wbtc));
        uint256 daiPrice = oracle.getAssetPrice(address(dai));
        {
            uint256 daiDepositAmount = 5e21; /* $5k */ // consider fuzzing here
            (, uint256 daiLtv,,,,,,,) = deployedContracts
                .protocolDataProvider
                .getReserveConfigurationData(address(dai), true);

            uint256 daiMaxBorrowAmount = daiLtv * daiDepositAmount / 10_000;

            uint256 wbtcMaxToBorrowRay = daiMaxBorrowAmount.rayDiv(wbtcPrice);
            uint256 wbtcMaxBorrowAmountWithDaiCollateral = fixture_preciseConvertWithDecimals(
                wbtcMaxToBorrowRay, dai.decimals(), wbtc.decimals()
            );
            require(
                wbtc.balanceOf(address(this)) > wbtcMaxBorrowAmountWithDaiCollateral,
                "Too less wbtc"
            );
            uint256 wbtcDepositAmount = wbtc.balanceOf(address(this)) / 2;

            /* Main user deposits usdc and wants to borrow */
            dai.approve(address(deployedContracts.lendingPool), daiDepositAmount);
            deployedContracts.lendingPool.deposit(
                address(dai), true, daiDepositAmount, address(this)
            );

            /* Other user deposits wbtc thanks to that there is enough funds to borrow */
            {
                address user = makeAddr("user");
                wbtc.approve(address(deployedContracts.lendingPool), wbtcDepositAmount);
                deployedContracts.lendingPool.deposit(address(wbtc), true, wbtcDepositAmount, user);
            }
            /* Main user borrows maxPossible amount of wbtc */
            deployedContracts.lendingPool.borrow(
                address(wbtc), true, wbtcMaxBorrowAmountWithDaiCollateral, address(this)
            );
        }
        {
            (,,,,, uint256 healthFactor) =
                deployedContracts.lendingPool.getUserAccountData(address(this));
            assertGe(healthFactor, 1 ether);
            // console.log("healthFactor: ", healthFactor);
        }

        /* simulate btc price increase */
        {
            priceIncrease = bound(priceIncrease, 800, 1_200); // 8-12%
            // console.log("wbtcPrice: ", wbtcPrice);
            uint256 newPrice = (wbtcPrice + wbtcPrice * priceIncrease / 10_000);
            // console.log("newPrice: ", newPrice);
            int256[] memory prices = new int256[](4);
            prices[0] = int256(newPrice);
            prices[1] = int256(oracle.getAssetPrice(address(weth)));
            prices[2] = int256(oracle.getAssetPrice(address(dai)));
            prices[3] = int256(oracle.getAssetPrice(address(cdxUsd)));
            address[] memory aggregators = new address[](4);
            (, aggregators) = fixture_getTokenPriceFeeds(erc20Tokens, prices);

            oracle.setAssetSources(tokens, aggregators);
            wbtcPrice = newPrice;
        }

        ReserveDataParams memory wbtcReserveParamsBefore =
            fixture_getReserveData(address(wbtc), deployedContracts.protocolDataProvider);
        {
            (,,,,, uint256 healthFactor) =
                deployedContracts.lendingPool.getUserAccountData(address(this));
            assertLt(healthFactor, 1 ether, "Health factor greater or equal than 1");
        }

        /**
         * LIQUIDATION PROCESS - START ***********
         */
        uint256 amountToLiquidate;
        uint256 scaledVariableDebt;
        {
            (, uint256 debtToCover, uint256 _scaledVariableDebt,,) = deployedContracts
                .protocolDataProvider
                .getUserReserveData(address(wbtc), true, address(this));
            amountToLiquidate = debtToCover / 2; // maximum possible liquidation amount
            scaledVariableDebt = _scaledVariableDebt;
        }
        {
            /* prepare funds */
            address liquidator = makeAddr("liquidator");
            wbtc.transfer(liquidator, amountToLiquidate);

            vm.startPrank(liquidator);
            wbtc.approve(address(deployedContracts.lendingPool), amountToLiquidate);
            deployedContracts.lendingPool.liquidationCall(
                address(dai), true, address(wbtc), true, address(this), amountToLiquidate, true
            );
            vm.stopPrank();
        }
        /**
         * LIQUIDATION PROCESS - END ***********
         */
        ReserveDataParams memory wbtcReserveParamsAfter =
            fixture_getReserveData(address(wbtc), deployedContracts.protocolDataProvider);
        uint256 expectedCollateralLiquidated;

        {
            (,,, uint256 liquidationBonus,,,,,) = deployedContracts
                .protocolDataProvider
                .getReserveConfigurationData(address(dai), true);

            expectedCollateralLiquidated = wbtcPrice
                * (amountToLiquidate * liquidationBonus / 10_000) * 10 ** dai.decimals()
                / (daiPrice * 10 ** wbtc.decimals());
        }
        uint256 variableDebtBeforeTx = fixture_calcExpectedVariableDebtTokenBalance(
            wbtcReserveParamsBefore.variableBorrowRate,
            wbtcReserveParamsBefore.variableBorrowIndex,
            wbtcReserveParamsBefore.lastUpdateTimestamp,
            scaledVariableDebt,
            block.timestamp
        );
        {
            (,,,,, uint256 healthFactor) =
                deployedContracts.lendingPool.getUserAccountData(address(this));
            // console.log("AFTER LIQUIDATION: ");
            // console.log("healthFactor: ", healthFactor);
            assertGt(healthFactor, 1 ether);
        }

        (, uint256 currentVariableDebt,,,) = deployedContracts
            .protocolDataProvider
            .getUserReserveData(address(wbtc), true, address(this));

        assertApproxEqRel(
            currentVariableDebt,
            variableDebtBeforeTx - amountToLiquidate,
            0.01e18,
            "VariableDebt assertion failed"
        );
        assertApproxEqRel(
            wbtcReserveParamsAfter.availableLiquidity,
            wbtcReserveParamsBefore.availableLiquidity + amountToLiquidate,
            0.01e18,
            "WBTC AvailableLiquidity assertion failed"
        );
        assertGe(
            wbtcReserveParamsAfter.liquidityIndex,
            wbtcReserveParamsBefore.liquidityIndex,
            "LiquidityIndex assertion failed"
        );
        assertLt(
            wbtcReserveParamsAfter.liquidityRate,
            wbtcReserveParamsBefore.liquidityRate,
            "LiquidityRate assertion failed"
        );

        assertApproxEqRel(
            aTokens[2].balanceOf(makeAddr("liquidator")),
            expectedCollateralLiquidated,
            0.01e18,
            "ADai AvailableLiquidity assertion failed"
        );
        {
            (,,,, bool usageAsCollateralEnabled) = deployedContracts
                .protocolDataProvider
                .getUserReserveData(address(dai), true, address(this));
            assertEq(usageAsCollateralEnabled, true);
        }
    }
}
