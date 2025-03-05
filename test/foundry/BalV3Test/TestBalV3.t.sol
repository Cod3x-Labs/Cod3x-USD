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

import {TestCdxUSDAndLend} from "test/helpers/TestCdxUSDAndLend.sol";
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

contract TestBalV3 is TestCdxUSDAndLend {
    IERC20[] public assets;
    address public stablePool;

    function setUp() public override {
        super.setUp();
        vm.selectFork(forkIdEth);
        assets.push(IERC20(address(counterAsset)));
        assets.push(IERC20(address(cdxUsd)));

        console2.log("assets[0] ::: ", address(assets[0]));
        console2.log("assets[1] ::: ", address(assets[1]));
    }

    function test_joinPool() public {
        stablePool = createStablePool(assets, 2500, address(this));

        assertEq(assets.length, 2);
        assertNotEq(stablePool, address(0));

        uint256[] memory amounts = new uint256[](assets.length);
        amounts[0] = 1e18;
        amounts[1] = 1e18;

        uint256 cdxUsdBalanceBefore = cdxUsd.balanceOf(userA);
        uint256 counterAssetBalanceBefore = counterAsset.balanceOf(userA);

        vm.startPrank(userA);
        tRouter.initialize(stablePool, assets, amounts);
        tRouter.addLiquidity(stablePool, userA, amounts);

        assertEq(counterAsset.balanceOf(userA), counterAssetBalanceBefore - amounts[0] * 2);
        assertEq(cdxUsd.balanceOf(userA), cdxUsdBalanceBefore - amounts[1] * 2);

        amounts[0] = 1e18;
        amounts[1] = 0;

        // get BPT token address
        IERC20[] memory tokens = IVaultExplorer(vaultV3).getPoolTokens(stablePool);
        console2.log("bptToken ::: ", tokens.length);

        IERC20(stablePool).approve(address(tRouter), type(uint256).max);

        tRouter.removeLiquidity(stablePool, userA, amounts);
        vm.stopPrank();

        assertEq(counterAsset.balanceOf(userA), counterAssetBalanceBefore - 1e18);
        assertEq(cdxUsd.balanceOf(userA), cdxUsdBalanceBefore - 2e18);

        cdxUsdBalanceBefore = cdxUsd.balanceOf(userA);
        counterAssetBalanceBefore = counterAsset.balanceOf(userA);

        vm.prank(userA);
        tRouter.swapSingleTokenExactIn(
            stablePool, cdxUsd, IERC20(address(counterAsset)), 1e18 / 2, 0
        );

        assertApproxEqRel(cdxUsd.balanceOf(userA), cdxUsdBalanceBefore - 1e18 / 2, 1e16); // 1%
        assertApproxEqRel(counterAsset.balanceOf(userA), counterAssetBalanceBefore + 1e18 / 2, 1e16); // 1%
    }
}
