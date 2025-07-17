// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import "forge-std/console2.sol";
import {TestCdxUSD} from "test/helpers/TestCdxUSD.sol";
import {ERC20Mock} from "../../helpers/mocks/ERC20Mock.sol";

/// reliquary imports
import "contracts/staking_module/reliquary/Reliquary.sol";
import "contracts/interfaces/IReliquary.sol";
import "contracts/staking_module/reliquary/nft_descriptors/NFTDescriptor.sol";
import "contracts/staking_module/reliquary/curves/LinearPlateauCurve.sol";
import "contracts/staking_module/reliquary/rewarders/RollingRewarder.sol";
import "contracts/staking_module/reliquary/rewarders/ParentRollingRewarder.sol";
import "contracts/interfaces/ICurves.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

/// vault imports
import {ReaperBaseStrategyv4} from "lib/Cod3x-Vault/src/ReaperBaseStrategyv4.sol";
import {ReaperVaultV2} from "lib/Cod3x-Vault/src/ReaperVaultV2.sol";
import {ScdxUsdVaultStrategy} from
    "contracts/staking_module/vault_strategy/ScdxUsdVaultStrategy.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "lib/Cod3x-Vault/test/vault/mock/FeeControllerMock.sol";

/// balancer V3 imports
import {BalancerV3Router} from
    "contracts/staking_module/vault_strategy/libraries/BalancerV3Router.sol";
import {
    TokenConfig,
    TokenType,
    PoolRoleAccounts,
    LiquidityManagement,
    AddLiquidityKind,
    RemoveLiquidityKind,
    AddLiquidityParams,
    RemoveLiquidityParams
} from "lib/balancer-v3-monorepo/pkg/interfaces/contracts/vault/VaultTypes.sol";
import {IVault} from "lib/balancer-v3-monorepo/pkg/interfaces/contracts/vault/IVault.sol";
import {Vault} from "lib/balancer-v3-monorepo/pkg/vault/contracts/Vault.sol";
import {StablePoolFactory} from
    "lib/balancer-v3-monorepo/pkg/pool-stable/contracts/StablePoolFactory.sol";
import {IRateProvider} from
    "lib/balancer-v3-monorepo/pkg/interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import {IVaultExplorer} from
    "lib/balancer-v3-monorepo/pkg/interfaces/contracts/vault/IVaultExplorer.sol";
import {TRouter} from "../../helpers/TRouter.sol";

/// Zap
import "contracts/staking_module/Zap.sol";

contract TestZap is TestCdxUSD, ERC721Holder {
    uint256 public constant MINIMAL_AMT = 1000000;

    bytes32 public poolId;
    address public poolAdd;
    IERC20[] public assets;
    IReliquary public reliquary;
    RollingRewarder public rewarder;
    ReaperVaultV2 public cod3xVault;
    ScdxUsdVaultStrategy public strategy;
    IERC20 public mockRewardToken;
    Zap public zap;
    TRouter public tRouter;
    BalancerV3Router public balancerV3Router;

    // Linear function config (to config)
    uint256 public slope = 100; // Increase of multiplier every second
    uint256 public minMultiplier = 365 days * 100; // Arbitrary (but should be coherent with slope)
    uint256 public plateau = 10 days;
    uint256 private constant RELIC_ID = 1;

    uint256 public indexCdxUsd;
    uint256 public indexUsdc; // usdt/usdc

    function setUp() public virtual override {
        super.setUp();
        vm.selectFork(forkIdEth);

        tRouter = new TRouter();
        vm.startPrank(userA);
        cdxUSD.approve(address(tRouter), type(uint256).max);
        usdc.approve(address(tRouter), type(uint256).max);
        vm.stopPrank();

        /// ======= Balancer Pool Deploy =======
        {
            assets.push(IERC20(address(usdc)));
            assets.push(IERC20(address(cdxUSD)));

            IERC20[] memory assetsSorted = sort(assets);
            assets[0] = assetsSorted[0];
            assets[1] = assetsSorted[1];

            // balancer stable pool creation
            poolAdd = createStablePool(assets, 2500, userA);

            // join Pool
            IERC20[] memory setupPoolTokens =
                IVaultExplorer(balancerContracts.balVault).getPoolTokens(poolAdd);

            uint256 indexCdxUsdTemp;
            uint256 indexUsdcTemp;
            for (uint256 i = 0; i < setupPoolTokens.length; i++) {
                if (setupPoolTokens[i] == cdxUSD) indexCdxUsdTemp = i;
                if (setupPoolTokens[i] == usdc) indexUsdcTemp = i;
            }

            uint256[] memory amountsToAdd = new uint256[](setupPoolTokens.length);
            amountsToAdd[indexCdxUsdTemp] = INITIAL_CDXUSD_AMT;
            amountsToAdd[indexUsdcTemp] = INITIAL_USDC_AMT;

            vm.prank(userA);
            tRouter.initialize(poolAdd, assets, amountsToAdd);

            vm.prank(userA);
            IERC20(poolAdd).transfer(address(this), 1);

            for (uint256 i = 0; i < assets.length; i++) {
                if (assets[i] == cdxUSD) indexCdxUsd = i;
                if (assets[i] == IERC20(address(usdc))) {
                    indexCdxUsd = i;
                }
            }
        }

        /// ========= Reliquary Deploy =========
        {
            mockRewardToken = IERC20(address(new ERC20Mock(18)));
            reliquary =
                new Reliquary(address(mockRewardToken), 0, "Reliquary scdxUSD", "scdxUSD Relic");
            address linearPlateauCurve =
                address(new LinearPlateauCurve(slope, minMultiplier, plateau));

            address nftDescriptor = address(new NFTDescriptor(address(reliquary)));

            address parentRewarder = address(new ParentRollingRewarder());

            Reliquary(address(reliquary)).grantRole(keccak256("OPERATOR"), address(this));
            Reliquary(address(reliquary)).grantRole(keccak256("GUARDIAN"), address(this));
            Reliquary(address(reliquary)).grantRole(keccak256("EMISSION_RATE"), address(this));

            IERC20(poolAdd).approve(address(reliquary), 1); // approve 1 wei to bootstrap the pool
            reliquary.addPool(
                100, // only one pool is necessary
                address(poolAdd), // BTP
                address(parentRewarder),
                ICurves(linearPlateauCurve),
                "scdxUSD Pool",
                nftDescriptor,
                true,
                address(this) // can send to the strategy directly.
            );

            rewarder =
                RollingRewarder(ParentRollingRewarder(parentRewarder).createChild(address(cdxUSD)));
            IERC20(cdxUSD).approve(address(reliquary), type(uint256).max);
            IERC20(cdxUSD).approve(address(rewarder), type(uint256).max);
        }

        /// ========== scdxUSD Vault Strategy Deploy ===========
        {
            address[] memory interactors = new address[](1);
            interactors[0] = address(this);
            balancerV3Router = new BalancerV3Router(
                address(balancerContracts.balVault), address(this), interactors
            );

            address[] memory ownerArr = new address[](3);
            ownerArr[0] = address(this);
            ownerArr[1] = address(this);
            ownerArr[2] = address(this);

            address[] memory ownerArr1 = new address[](1);
            ownerArr[0] = address(this);

            FeeControllerMock feeControllerMock = new FeeControllerMock();
            feeControllerMock.updateManagementFeeBPS(0);

            cod3xVault = new ReaperVaultV2(
                poolAdd,
                "Staked Cod3x USD",
                "scdxUSD",
                type(uint256).max,
                0,
                extContracts.treasury,
                ownerArr,
                ownerArr,
                address(feeControllerMock)
            );

            ScdxUsdVaultStrategy implementation = new ScdxUsdVaultStrategy();
            ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), "");
            strategy = ScdxUsdVaultStrategy(address(proxy));

            reliquary.transferFrom(address(this), address(strategy), RELIC_ID); // transfer Relic#1 to strategy.
            strategy.initialize(
                address(cod3xVault),
                address(balancerContracts.balVault),
                address(balancerV3Router),
                ownerArr1,
                ownerArr,
                ownerArr1,
                address(cdxUSD),
                address(reliquary),
                address(poolAdd)
            );

            // console2.log(address(cod3xVault));
            // console2.log(address(balancerContracts.balVault));
            // console2.log(address(cdxUSD));
            // console2.log(address(reliquary));
            // console2.log(address(poolAdd));

            cod3xVault.addStrategy(address(strategy), 0, 10_000); // 100 % invested
        }

        /// ========== Zap Deploy ===========
        {
            zap = new Zap(
                address(balancerContracts.balVault),
                address(cod3xVault),
                address(balancerV3Router),
                address(strategy),
                address(reliquary),
                address(cdxUSD),
                address(usdc),
                address(this),
                address(this)
            );

            address[] memory interactors2 = new address[](2);
            interactors2[0] = address(zap);
            interactors2[1] = address(strategy);
            balancerV3Router.setInteractors(interactors2);
        }

        // MAX approve `cod3xVault` and `zap` by all users
        for (uint160 i = 1; i <= 4; i++) {
            vm.startPrank(address(i)); // address(0x1) == address(1)

            IERC20(poolAdd).approve(address(cod3xVault), type(uint256).max);

            IERC20(cdxUSD).approve(address(zap), type(uint256).max);
            IERC20(usdc).approve(address(zap), type(uint256).max);

            cod3xVault.approve(address(zap), type(uint256).max);

            IERC20(poolAdd).approve(address(reliquary), type(uint256).max);

            cdxUSD.approve(address(tRouter), type(uint256).max);
            usdc.approve(address(tRouter), type(uint256).max);

            cdxUSD.approve(address(balancerV3Router), type(uint256).max);
            usdc.approve(address(balancerV3Router), type(uint256).max);

            IERC20(poolAdd).approve(address(balancerV3Router), type(uint256).max);

            vm.stopPrank();
        }
    }

    function testZapInStakedCdxUSD(uint256 _seedAmtCdxusd, uint256 _seedAmtUsdc) public {
        uint256 amtCdxusd = bound(_seedAmtCdxusd, MINIMAL_AMT, IERC20(cdxUSD).balanceOf(userB));
        uint256 amtUsdc = bound(_seedAmtUsdc, MINIMAL_AMT, IERC20(usdc).balanceOf(userB));

        uint256 balanceBeforeCdxusd = IERC20(cdxUSD).balanceOf(userB);
        uint256 balanceBeforeUsdc = IERC20(usdc).balanceOf(userB);

        vm.prank(userB);
        zap.zapInStakedCdxUSD(amtCdxusd, amtUsdc, userC, 1);

        assertApproxEqRel(cod3xVault.balanceOf(userC), amtCdxusd + scaleDecimal(amtUsdc), 1e15); // 0,1%

        assertEq(IERC20(cdxUSD).balanceOf(userB), balanceBeforeCdxusd - amtCdxusd);
        assertEq(IERC20(usdc).balanceOf(userB), balanceBeforeUsdc - amtUsdc);

        checkBalanceInvariant();
    }

    function testZapOutStakedCdxUSD(
        uint256 _seedAmtCdxusd,
        uint256 _seedAmtUsdc,
        uint256 _seedTokenIndex
    ) public {
        uint256 amtCdxusd = bound(_seedAmtCdxusd, 1e18, IERC20(cdxUSD).balanceOf(userB));
        uint256 amtUsdc = bound(_seedAmtUsdc, MINIMAL_AMT, IERC20(usdc).balanceOf(userB));
        uint256 tokenIndex = bound(_seedTokenIndex, 0, 1);

        IERC20 tokenToWithdraw;
        if (tokenIndex == indexCdxUsd) tokenToWithdraw = cdxUSD;
        else if (tokenIndex == indexUsdc) tokenToWithdraw = usdc;

        vm.prank(userB);
        zap.zapInStakedCdxUSD(amtCdxusd, amtUsdc, userC, 1);
        vm.startPrank(userC);
        zap.zapOutStakedCdxUSD(
            cod3xVault.balanceOf(userC) / 10, address(tokenToWithdraw), 1, address(999)
        );
        vm.stopPrank();

        assertApproxEqRel(
            tokenIndex == indexCdxUsd
                ? tokenToWithdraw.balanceOf(address(999))
                : scaleDecimal(tokenToWithdraw.balanceOf(address(999))),
            (amtCdxusd + scaleDecimal(amtUsdc)) / 10,
            2e15
        ); // 0,2%

        checkBalanceInvariant();
    }

    function testZapInRelicCreate(uint256 _seedAmtCdxusd, uint256 _seedAmtUsdc) public {
        uint256 amtCdxusd = bound(_seedAmtCdxusd, MINIMAL_AMT, IERC20(cdxUSD).balanceOf(userB));
        uint256 amtUsdc = bound(_seedAmtUsdc, MINIMAL_AMT, IERC20(usdc).balanceOf(userB));

        uint256 balanceBeforeCdxusd = IERC20(cdxUSD).balanceOf(userB);
        uint256 balanceBeforeUsdc = IERC20(usdc).balanceOf(userB);

        vm.prank(userB);
        zap.zapInRelic(0, amtCdxusd, amtUsdc, userC, 1);

        assertEq(reliquary.balanceOf(userC), 1);

        assertApproxEqRel(amtCdxusd + scaleDecimal(amtUsdc), reliquary.getAmountInRelic(2), 1e15); // relic 2

        assertEq(IERC20(cdxUSD).balanceOf(userB), balanceBeforeCdxusd - amtCdxusd);
        assertEq(IERC20(usdc).balanceOf(userB), balanceBeforeUsdc - amtUsdc);

        checkBalanceInvariant();
    }

    function testZapInRelicOwned(uint256 _seedAmtCdxusd, uint256 _seedAmtUsdc) public {
        uint256 amtCdxusd = bound(_seedAmtCdxusd, MINIMAL_AMT, IERC20(cdxUSD).balanceOf(userB));
        uint256 amtUsdc = bound(_seedAmtUsdc, MINIMAL_AMT, IERC20(usdc).balanceOf(userB));

        uint256 initialRelicAmt = 1000e18;

        uint256 balanceBeforeCdxusd = IERC20(cdxUSD).balanceOf(userB);
        uint256 balanceBeforeUsdc = IERC20(usdc).balanceOf(userB);

        vm.prank(userA);
        reliquary.createRelicAndDeposit(userB, 0, initialRelicAmt);
        assertEq(reliquary.balanceOf(userA), 0);
        assertEq(reliquary.balanceOf(userB), 1);
        assertEq(reliquary.getAmountInRelic(2), initialRelicAmt);

        vm.startPrank(userB);
        reliquary.approve(address(zap), 2);
        zap.zapInRelic(2, amtCdxusd, amtUsdc, userB, 1);
        vm.stopPrank();

        assertEq(reliquary.balanceOf(userB), 1);

        assertApproxEqRel(
            amtCdxusd + scaleDecimal(amtUsdc) + initialRelicAmt, reliquary.getAmountInRelic(2), 1e15
        ); // relic 2

        assertEq(IERC20(cdxUSD).balanceOf(userB), balanceBeforeCdxusd - amtCdxusd);
        assertEq(IERC20(usdc).balanceOf(userB), balanceBeforeUsdc - amtUsdc);

        checkBalanceInvariant();
    }

    function testZapInRelicOwnedRevert1(uint256 _seedAmtCdxusd, uint256 _seedAmtUsdc) public {
        uint256 amtCdxusd = bound(_seedAmtCdxusd, MINIMAL_AMT, IERC20(cdxUSD).balanceOf(userB));
        uint256 amtUsdc = bound(_seedAmtUsdc, MINIMAL_AMT, IERC20(usdc).balanceOf(userB));

        uint256 initialRelicAmt = 1000e18;

        vm.prank(userA);
        reliquary.createRelicAndDeposit(userB, 0, initialRelicAmt);
        assertEq(reliquary.balanceOf(userA), 0);
        assertEq(reliquary.balanceOf(userB), 1);
        assertEq(reliquary.getAmountInRelic(2), initialRelicAmt);

        vm.startPrank(userB);
        reliquary.approve(address(zap), 2);
        vm.expectRevert(Zap.Zap__RELIC_NOT_OWNED.selector);
        zap.zapInRelic(2, amtCdxusd, amtUsdc, userC, 1);
        vm.stopPrank();

        assertEq(reliquary.balanceOf(userB), 1);

        checkBalanceInvariant();
    }

    function testZapInRelicOwnedRevert2(uint256 _seedAmtCdxusd, uint256 _seedAmtUsdc) public {
        uint256 amtCdxusd = bound(_seedAmtCdxusd, MINIMAL_AMT, IERC20(cdxUSD).balanceOf(userB));
        uint256 amtUsdc = bound(_seedAmtUsdc, MINIMAL_AMT, IERC20(usdc).balanceOf(userB));

        uint256 initialRelicAmt = 1000e18;

        vm.prank(userA);
        reliquary.createRelicAndDeposit(userC, 0, initialRelicAmt);
        assertEq(reliquary.balanceOf(userA), 0);
        assertEq(reliquary.balanceOf(userC), 1);
        assertEq(reliquary.getAmountInRelic(2), initialRelicAmt);

        vm.prank(userC);
        reliquary.approve(address(zap), 2);

        vm.startPrank(userB);
        vm.expectRevert(Zap.Zap__RELIC_NOT_OWNED.selector);
        zap.zapInRelic(2, amtCdxusd, amtUsdc, userB, 1);
        vm.stopPrank();

        checkBalanceInvariant();
    }

    function testZapOutRelicOwned1(uint256 _seedInitialRelicAmt, uint256 _seedTokenIndex) public {
        uint256 initialRelicAmt =
            bound(_seedInitialRelicAmt, 1e18, IERC20(poolAdd).balanceOf(userA) / 10);
        uint256 tokenIndex = bound(_seedTokenIndex, 0, 1);

        IERC20 tokenToWithdraw;
        if (tokenIndex == indexCdxUsd) tokenToWithdraw = cdxUSD;
        else if (tokenIndex == indexUsdc) tokenToWithdraw = usdc;

        // uint256 initialBlalance = IERC20(poolAdd).balanceOf(userA);
        // uint256 balanceBeforeUsdc = IERC20(usdc).balanceOf(userB);

        vm.prank(userA);
        reliquary.createRelicAndDeposit(userA, 0, initialRelicAmt);
        assertEq(reliquary.balanceOf(userA), 1);
        assertEq(reliquary.getAmountInRelic(2), initialRelicAmt);

        vm.startPrank(userA);
        reliquary.approve(address(zap), 2);
        zap.zapOutRelic(2, initialRelicAmt, address(tokenToWithdraw), 1, userA);
        vm.stopPrank();

        // assertApproxEqRel(initialRelicAmt, tokenToWithdraw.balanceOf(userA), 1e15);
        assertEq(0, reliquary.getAmountInRelic(2));

        checkBalanceInvariant();
    }

    function testZapOutRelicOwned2(
        uint256 _seedAmtCdxusd,
        uint256 _seedAmtUsdc,
        uint256 _seedTokenIndex
    ) public {
        uint256 amtCdxusd = bound(_seedAmtCdxusd, MINIMAL_AMT, IERC20(cdxUSD).balanceOf(userB) / 10);
        uint256 amtUsdc = bound(_seedAmtUsdc, MINIMAL_AMT, IERC20(usdc).balanceOf(userB) / 10);
        uint256 tokenIndex = bound(_seedTokenIndex, 0, 1);

        uint256 initialBlalance1 = cdxUSD.balanceOf(userB);
        uint256 initialBlalance3 = scaleDecimal(usdc.balanceOf(userB));

        vm.prank(userB);
        zap.zapInRelic(0, amtCdxusd, amtUsdc, userB, 1);

        assertEq(reliquary.balanceOf(userB), 1);

        assertApproxEqRel(amtCdxusd + scaleDecimal(amtUsdc), reliquary.getAmountInRelic(2), 1e15); // relic 2

        vm.startPrank(userB);
        reliquary.approve(address(zap), 2);
        zap.zapOutRelic(2, reliquary.getAmountInRelic(2), address(assets[tokenIndex]), 1, userB);
        vm.stopPrank();

        assertApproxEqRel(
            initialBlalance1 + initialBlalance3,
            cdxUSD.balanceOf(userB) + scaleDecimal(usdc.balanceOf(userB)),
            5e15
        );
        assertEq(0, reliquary.getAmountInRelic(2));

        checkBalanceInvariant();
    }

    // function testZapOutRelicOwnedRevert(
    //     uint256 _seedAmtCdxusd,
    //     uint256 _seedAmtUsdc,
    //     uint256 _seedTokenIndex
    // ) public {
    //     uint256 amtCdxusd = bound(_seedAmtCdxusd, MINIMAL_AMT, IERC20(cdxUSD).balanceOf(userB) / 10);
    //     uint256 amtUsdc = bound(_seedAmtUsdc, MINIMAL_AMT, IERC20(usdc).balanceOf(userB) / 10);
    //     uint256 tokenIndex = bound(_seedTokenIndex, 0, 2);

    //     IERC20 tokenToWithdraw;
    //     if (tokenIndex == 0) tokenToWithdraw = cdxUSD;
    //     else if (tokenIndex == 2) tokenToWithdraw = usdc;

    //     vm.prank(userB);
    //     zap.zapInRelic(0, amtCdxusd, amtUsdc, userB, 1);

    //     assertEq(reliquary.balanceOf(userB), 1);

    //     assertApproxEqRel(
    //         amtCdxusd + scaleDecimal(amtUsdc),
    //         reliquary.getAmountInRelic(2),
    //         1e15
    //     ); // relic 2

    //     vm.startPrank(userB);
    //     reliquary.approve(address(zap), 2);
    //     vm.stopPrank();

    //     vm.expectRevert(Zap.Zap__RELIC_NOT_OWNED.selector);
    //     zap.zapOutRelic(2, reliquary.getAmountInRelic(2), address(assets[tokenIndex]), 1, userC);

    //     checkBalanceInvariant();
    // }

    /// ============ Helpers ============

    function checkBalanceInvariant() internal {
        assertEq(cdxUSD.balanceOf(address(zap)), 0);
        assertEq(usdc.balanceOf(address(zap)), 0);
        assertEq(IERC20(poolAdd).balanceOf(address(zap)), 0);
        assertEq(reliquary.balanceOf(address(zap)), 0);
    }

    function scaleDecimal(uint256 amt) internal pure returns (uint256) {
        return amt * 10 ** (18 - 6);
    }
}
