// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/console2.sol";

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

// Balancer
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

    IERC20 public counterAsset2;
    address public poolAdd2;
    IERC20[] public assets2;

    uint256 indexCdxUsd2;
    uint256 indexCounterAsset2;

    function setUp() public override {
        super.setUp();

        counterAsset2 = IERC20(address(new ERC20Mock(8)));

        /// initial mint
        ERC20Mock(address(counterAsset2)).mint(userA, INITIAL_COUNTER_ASSET_AMT);
        ERC20Mock(address(counterAsset2)).mint(userB, INITIAL_COUNTER_ASSET_AMT);
        ERC20Mock(address(counterAsset2)).mint(userC, INITIAL_COUNTER_ASSET_AMT);
        vm.startPrank(userC);
        ERC20Mock(address(cdxUsd)).mint(userC, INITIAL_CDXUSD_AMT);
        vm.stopPrank();

        vm.startPrank(userC); // address(0x1) == address(1)
        cdxUsdContract.approve(address(balancerContracts.balVault), type(uint256).max);
        counterAsset2.approve(address(balancerContracts.balVault), type(uint256).max);
        cdxUsdContract.approve(address(tRouter), type(uint256).max);
        counterAsset2.approve(address(tRouter), type(uint256).max);
        vm.stopPrank();

        address[] memory interactors = new address[](4);
        interactors[0] = address(this);
        interactors[1] = address(userA);
        interactors[2] = address(userB);
        interactors[3] = address(userC);

        router = new BalancerV3Router(balancerContracts.balVault, address(this), interactors);

        // ======= Balancer Pool 2 Deploy =======
        {
            assets2.push(IERC20(address(counterAsset2)));
            assets2.push(IERC20(address(cdxUsd)));

            IERC20[] memory assetsSorted = sort(assets2);
            assets2[0] = assetsSorted[0];
            assets2[1] = assetsSorted[1];

            // balancer stable pool creation
            poolAdd2 = createStablePool(assets2, 2500, userC);

            // join Pool
            IERC20[] memory setupPoolTokens =
                IVaultExplorer(balancerContracts.balVault).getPoolTokens(poolAdd2);

            for (uint256 i = 0; i < setupPoolTokens.length; i++) {
                if (setupPoolTokens[i] == cdxUsdContract) indexCdxUsd2 = i;
                if (setupPoolTokens[i] == IERC20(address(counterAsset2))) indexCounterAsset2 = i;
            }

            uint256[] memory amountsToAdd = new uint256[](setupPoolTokens.length);
            amountsToAdd[indexCdxUsd2] = 1_000_000e18;
            amountsToAdd[indexCounterAsset2] = 1_000_000e8;

            vm.prank(userC);
            tRouter.initialize(poolAdd2, assets2, amountsToAdd);

            vm.prank(userC);
            IERC20(poolAdd2).transfer(address(this), 1);

            for (uint256 i = 0; i < assets2.length; i++) {
                if (assets2[i] == cdxUsdContract) indexCdxUsd = i;
                if (assets2[i] == IERC20(address(counterAsset2))) {
                    indexCounterAsset = i;
                }
            }
        }

        // all user approve max router
        for (uint256 i = 0; i < interactors.length; i++) {
            vm.startPrank(interactors[i]);
            cdxUsdContract.approve(address(router), type(uint256).max);
            counterAsset.approve(address(router), type(uint256).max);
            counterAsset2.approve(address(router), type(uint256).max);
            IERC20(poolAdd).approve(address(router), type(uint256).max);
            IERC20(poolAdd2).approve(address(router), type(uint256).max);
            vm.stopPrank();
        }
    }

    // Make sure 18decScaled(balancesRaw_) == lastBalancesLiveScaled18_
    function test_getPoolTokenInfo() public {
        {
            (
                IERC20[] memory tokens_,
                ,
                uint256[] memory balancesRaw_,
                uint256[] memory lastBalancesLiveScaled18_
            ) = IVaultExplorer(balancerContracts.balVault).getPoolTokenInfo(poolAdd2);

            for (uint256 i = 0; i < tokens_.length; i++) {
                console2.log("token ::: ", address(tokens_[i]));
                console2.log("balanceRaw              ::: ", balancesRaw_[i]);
                console2.log("lastBalanceLiveScaled18 ::: ", lastBalancesLiveScaled18_[i]);
                console2.log("--------------------------------");

                assertEq(scaleDecimals(balancesRaw_[i], tokens_[i]), lastBalancesLiveScaled18_[i]);
            }
        }

        // add liquidity
        uint256[] memory amountsToAdd = new uint256[](assets2.length);
        amountsToAdd[indexCdxUsd2] = 101100e18;
        amountsToAdd[indexCounterAsset2] = 1900e8;

        vm.startPrank(userB);
        router.addLiquidityUnbalanced(poolAdd2, amountsToAdd, 0);
        vm.stopPrank();

        {
            (
                IERC20[] memory tokens_,
                ,
                uint256[] memory balancesRaw_,
                uint256[] memory lastBalancesLiveScaled18_
            ) = IVaultExplorer(balancerContracts.balVault).getPoolTokenInfo(poolAdd2);

            for (uint256 i = 0; i < tokens_.length; i++) {
                console2.log("token ::: ", address(tokens_[i]));
                console2.log("balanceRaw              ::: ", balancesRaw_[i]);
                console2.log("lastBalanceLiveScaled18 ::: ", lastBalancesLiveScaled18_[i]);
                console2.log("--------------------------------");

                assertEq(scaleDecimals(balancesRaw_[i], tokens_[i]), lastBalancesLiveScaled18_[i]);
            }
        }

        // remove liquidity
        vm.startPrank(userB);
        router.removeLiquiditySingleTokenExactIn(poolAdd2, 0, IERC20(poolAdd2).balanceOf(userB), 1);
        vm.stopPrank();

        {
            (
                IERC20[] memory tokens_,
                ,
                uint256[] memory balancesRaw_,
                uint256[] memory lastBalancesLiveScaled18_
            ) = IVaultExplorer(balancerContracts.balVault).getPoolTokenInfo(poolAdd2);

            for (uint256 i = 0; i < tokens_.length; i++) {
                console2.log("token ::: ", address(tokens_[i]));
                console2.log("balanceRaw              ::: ", balancesRaw_[i]);
                console2.log("lastBalanceLiveScaled18 ::: ", lastBalancesLiveScaled18_[i]);
                console2.log("--------------------------------");

                assertEq(scaleDecimals(balancesRaw_[i], tokens_[i]), lastBalancesLiveScaled18_[i]);
            }
        }
    }

    function test_BalancerV3Router1() public {
        uint256[] memory amounts = new uint256[](assets.length);
        amounts[0] = 1e18;
        amounts[1] = 1e18;

        // balance before
        uint256 cdxUsdBalanceBefore = cdxUsdContract.balanceOf(userB);
        uint256 counterAssetBalanceBefore = counterAsset.balanceOf(userB);

        vm.startPrank(userB);
        router.addLiquidityUnbalanced(poolAdd, amounts, 0);
        vm.stopPrank();

        assertEq(cdxUsdContract.balanceOf(userB), cdxUsdBalanceBefore - amounts[0]);
        assertEq(counterAsset.balanceOf(userB), counterAssetBalanceBefore - amounts[1]);

        // remove liquidity
        uint256[] memory amountsOut = new uint256[](assets.length);
        amountsOut[0] = 1e18;
        amountsOut[1] = 1e18;

        // balance before remove liquidity
        uint256 cdxUsdBalanceBeforeRemove = cdxUsdContract.balanceOf(userB);
        uint256 counterAssetBalanceBeforeRemove = counterAsset.balanceOf(userB);

        vm.startPrank(userB);
        router.removeLiquiditySingleTokenExactIn(poolAdd, 0, IERC20(poolAdd).balanceOf(userB), 1);
        vm.stopPrank();

        console2.log(
            "cdxUsd.balanceOf(userB) ::: ",
            cdxUsdContract.balanceOf(userB) - cdxUsdBalanceBeforeRemove
        );
        console2.log(
            "counterAsset.balanceOf(userB) ::: ",
            counterAsset.balanceOf(userB) - counterAssetBalanceBeforeRemove
        );

        assertApproxEqRel(cdxUsdContract.balanceOf(userB) - cdxUsdBalanceBeforeRemove, 2e18, 1e16);
        assertEq(IERC20(poolAdd).balanceOf(userB), 0);
    }

    function test_BalancerV3Router2() public {
        uint256[] memory amounts = new uint256[](assets.length);
        amounts[0] = 1e18;
        amounts[1] = 1e18;

        // balance before
        uint256 cdxUsdBalanceBefore = cdxUsdContract.balanceOf(userB);
        uint256 counterAssetBalanceBefore = counterAsset.balanceOf(userB);

        vm.startPrank(userB);
        router.addLiquidityUnbalanced(poolAdd, amounts, 0);
        vm.stopPrank();

        assertEq(cdxUsdContract.balanceOf(userB), cdxUsdBalanceBefore - amounts[0]);
        assertEq(counterAsset.balanceOf(userB), counterAssetBalanceBefore - amounts[1]);

        // remove liquidity
        uint256[] memory amountsOut = new uint256[](assets.length);
        amountsOut[0] = 1e18;
        amountsOut[1] = 1e18;

        // balance before remove liquidity
        uint256 cdxUsdBalanceBeforeRemove = cdxUsdContract.balanceOf(userB);
        uint256 counterAssetBalanceBeforeRemove = counterAsset.balanceOf(userB);

        vm.startPrank(userB);
        router.removeLiquiditySingleTokenExactIn(poolAdd, 1, IERC20(poolAdd).balanceOf(userB), 1);
        vm.stopPrank();

        console2.log(
            "cdxUsd.balanceOf(userB) ::: ",
            cdxUsdContract.balanceOf(userB) - cdxUsdBalanceBeforeRemove
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

    function test_TRouter() public {
        assertEq(assets.length, 2);
        assertNotEq(poolAdd, address(0));

        uint256[] memory amounts = new uint256[](assets.length);
        amounts[0] = 1e18;
        amounts[1] = 1e18;

        uint256 cdxUsdBalanceBefore = cdxUsdContract.balanceOf(userB);
        uint256 counterAssetBalanceBefore = counterAsset.balanceOf(userB);

        vm.startPrank(userB);
        tRouter.addLiquidity(poolAdd, userB, amounts);

        assertEq(counterAsset.balanceOf(userB), counterAssetBalanceBefore - amounts[0]);
        assertEq(cdxUsdContract.balanceOf(userB), cdxUsdBalanceBefore - amounts[1]);

        amounts[0] = 0;
        amounts[1] = 1e18;

        // get BPT token address
        IERC20[] memory tokens = IVaultExplorer(balancerContracts.balVault).getPoolTokens(poolAdd);
        console2.log("bptToken ::: ", tokens.length);

        IERC20(poolAdd).approve(address(tRouter), type(uint256).max);

        tRouter.removeLiquidity(poolAdd, userB, amounts);
        vm.stopPrank();

        assertEq(counterAsset.balanceOf(userB), counterAssetBalanceBefore);
        assertEq(cdxUsdContract.balanceOf(userB), cdxUsdBalanceBefore - 1e18);

        cdxUsdBalanceBefore = cdxUsdContract.balanceOf(userB);
        counterAssetBalanceBefore = counterAsset.balanceOf(userB);

        vm.prank(userB);
        tRouter.swapSingleTokenExactIn(
            poolAdd, cdxUsdContract, IERC20(address(counterAsset)), 1e18 / 2, 0
        );

        assertApproxEqRel(cdxUsdContract.balanceOf(userB), cdxUsdBalanceBefore - 1e18 / 2, 1e16); // 1%
        assertApproxEqRel(counterAsset.balanceOf(userB), counterAssetBalanceBefore + 1e18 / 2, 1e16); // 1%
    }

    /// ================ Helper functions ================

    /**
     * @notice Scales an amount to the appropriate number of decimals (18) based on the token's decimal precision.
     * @param amount The value representing the amount to be scaled.
     * @param token The address of the IERC20 token contract.
     * @return The scaled amount.
     */
    function scaleDecimals(uint256 amount, IERC20 token) internal view returns (uint256) {
        return amount * 10 ** (18 - ERC20(address(token)).decimals());
    }
}
