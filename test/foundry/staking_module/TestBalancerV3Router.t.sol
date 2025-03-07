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
import {IVault, JoinKind, ExitKind, SwapKind} from "contracts/interfaces/IVault.sol";
import {
    IComposableStablePoolFactory,
    IRateProvider,
    ComposableStablePool
} from "contracts/interfaces/IComposableStablePoolFactory.sol";
import "forge-std/console2.sol";

import {TestCdxUSDAndLendAndStaking} from "test/helpers/TestCdxUSDAndLendAndStaking.sol";
import {ERC20Mock} from "../../helpers/mocks/ERC20Mock.sol";

// reliquary
import "contracts/staking_module/reliquary/Reliquary.sol";
import "contracts/interfaces/IReliquary.sol";
import "contracts/staking_module/reliquary/nft_descriptors/NFTDescriptor.sol";
import "contracts/staking_module/reliquary/curves/LinearPlateauCurve.sol";
import "contracts/staking_module/reliquary/rewarders/RollingRewarder.sol";
import "contracts/staking_module/reliquary/rewarders/ParentRollingRewarder.sol";
import "contracts/interfaces/ICurves.sol";
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

import {IERC20Detailed} from
    "lib/Cod3x-Lend/contracts/dependencies/openzeppelin/contracts/IERC20Detailed.sol";
import {TRouter} from "test/helpers/TRouter.sol";
import {IVaultExplorer} from
    "lib/balancer-v3-monorepo/pkg/interfaces/contracts/vault/IVaultExplorer.sol";

import {BalancerV3Router} from
    "contracts/staking_module/vault_strategy/libraries/BalancerV3Router.sol";

contract TestBalancerV3Router is TestCdxUSDAndLendAndStaking {
    BalancerV3Router public router;

    function setUp() public override {
        super.setUp();

        address[] memory interactors = new address[](4);
        interactors[0] = address(this);
        interactors[1] = address(userA);
        interactors[2] = address(userB);
        interactors[3] = address(userC);

        router = new BalancerV3Router(vaultV3, address(this), interactors);

        // all user approve max router
        for (uint256 i = 0; i < interactors.length; i++) {
            vm.startPrank(interactors[i]);
            cdxUsd.approve(address(router), type(uint256).max);
            counterAsset.approve(address(router), type(uint256).max);
            IERC20(poolAdd).approve(address(router), type(uint256).max);
            vm.stopPrank();
        }
    }

    function test_BalancerV3Router1() public {
        uint256[] memory amounts = new uint256[](assets.length);
        amounts[0] = 1e18;
        amounts[1] = 1e18;

        // balance before
        uint256 cdxUsdBalanceBefore = cdxUsd.balanceOf(userB);
        uint256 counterAssetBalanceBefore = counterAsset.balanceOf(userB);

        vm.startPrank(userB);
        router.addLiquidityUnbalanced(poolAdd, amounts, 0);
        vm.stopPrank();

        assertEq(cdxUsd.balanceOf(userB), cdxUsdBalanceBefore - amounts[0]);
        assertEq(counterAsset.balanceOf(userB), counterAssetBalanceBefore - amounts[1]);

        // remove liquidity
        uint256[] memory amountsOut = new uint256[](assets.length);
        amountsOut[0] = 1e18;
        amountsOut[1] = 1e18;

        // balance before remove liquidity
        uint256 cdxUsdBalanceBeforeRemove = cdxUsd.balanceOf(userB);
        uint256 counterAssetBalanceBeforeRemove = counterAsset.balanceOf(userB);

        vm.startPrank(userB);
        router.removeLiquiditySingleTokenExactIn(poolAdd, 0, IERC20(poolAdd).balanceOf(userB), 1);
        vm.stopPrank();

        console2.log(
            "cdxUsd.balanceOf(userB) ::: ", cdxUsd.balanceOf(userB) - cdxUsdBalanceBeforeRemove
        );
        console2.log(
            "counterAsset.balanceOf(userB) ::: ",
            counterAsset.balanceOf(userB) - counterAssetBalanceBeforeRemove
        );

        assertApproxEqRel(
            counterAsset.balanceOf(userB) - counterAssetBalanceBeforeRemove, 2e18, 1e16
        );
        assertEq(IERC20(poolAdd).balanceOf(userB), 0);
    }

    function test_BalancerV3Router2() public {
        uint256[] memory amounts = new uint256[](assets.length);
        amounts[0] = 1e18;
        amounts[1] = 1e18;

        // balance before
        uint256 cdxUsdBalanceBefore = cdxUsd.balanceOf(userB);
        uint256 counterAssetBalanceBefore = counterAsset.balanceOf(userB);

        vm.startPrank(userB);
        router.addLiquidityUnbalanced(poolAdd, amounts, 0);
        vm.stopPrank();

        assertEq(cdxUsd.balanceOf(userB), cdxUsdBalanceBefore - amounts[0]);
        assertEq(counterAsset.balanceOf(userB), counterAssetBalanceBefore - amounts[1]);

        // remove liquidity
        uint256[] memory amountsOut = new uint256[](assets.length);
        amountsOut[0] = 1e18;
        amountsOut[1] = 1e18;

        // balance before remove liquidity
        uint256 cdxUsdBalanceBeforeRemove = cdxUsd.balanceOf(userB);
        uint256 counterAssetBalanceBeforeRemove = counterAsset.balanceOf(userB);

        vm.startPrank(userB);
        router.removeLiquiditySingleTokenExactIn(poolAdd, 1, IERC20(poolAdd).balanceOf(userB), 1);
        vm.stopPrank();

        console2.log(
            "cdxUsd.balanceOf(userB) ::: ", cdxUsd.balanceOf(userB) - cdxUsdBalanceBeforeRemove
        );
        console2.log(
            "counterAsset.balanceOf(userB) ::: ",
            counterAsset.balanceOf(userB) - counterAssetBalanceBeforeRemove
        );

        assertApproxEqRel(cdxUsd.balanceOf(userB) - cdxUsdBalanceBeforeRemove, 2e18, 1e16);
        assertEq(IERC20(poolAdd).balanceOf(userB), 0);
    }

    function test_TRouter() public {
        assertEq(assets.length, 2);
        assertNotEq(poolAdd, address(0));

        uint256[] memory amounts = new uint256[](assets.length);
        amounts[0] = 1e18;
        amounts[1] = 1e18;

        uint256 cdxUsdBalanceBefore = cdxUsd.balanceOf(userB);
        uint256 counterAssetBalanceBefore = counterAsset.balanceOf(userB);

        vm.startPrank(userB);
        tRouter.addLiquidity(poolAdd, userB, amounts);

        assertEq(counterAsset.balanceOf(userB), counterAssetBalanceBefore - amounts[0]);
        assertEq(cdxUsd.balanceOf(userB), cdxUsdBalanceBefore - amounts[1]);

        amounts[0] = 1e18;
        amounts[1] = 0;

        // get BPT token address
        IERC20[] memory tokens = IVaultExplorer(vaultV3).getPoolTokens(poolAdd);
        console2.log("bptToken ::: ", tokens.length);

        IERC20(poolAdd).approve(address(tRouter), type(uint256).max);

        tRouter.removeLiquidity(poolAdd, userB, amounts);
        vm.stopPrank();

        assertEq(counterAsset.balanceOf(userB), counterAssetBalanceBefore);
        assertEq(cdxUsd.balanceOf(userB), cdxUsdBalanceBefore - 1e18);

        cdxUsdBalanceBefore = cdxUsd.balanceOf(userB);
        counterAssetBalanceBefore = counterAsset.balanceOf(userB);

        vm.prank(userB);
        tRouter.swapSingleTokenExactIn(poolAdd, cdxUsd, IERC20(address(counterAsset)), 1e18 / 2, 0);

        assertApproxEqRel(cdxUsd.balanceOf(userB), cdxUsdBalanceBefore - 1e18 / 2, 1e16); // 1%
        assertApproxEqRel(counterAsset.balanceOf(userB), counterAssetBalanceBefore + 1e18 / 2, 1e16); // 1%
    }
}
