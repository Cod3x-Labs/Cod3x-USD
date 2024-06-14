// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
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

import {TestCdxUSD} from "test/helpers/TestCdxUSD.sol";

// reliquary
import "contracts/staking_module/reliquary/Reliquary.sol";
import "contracts/staking_module/reliquary/nft_descriptors/NFTDescriptor.sol";
import "contracts/staking_module/reliquary/curves/LinearPlateauCurve.sol";
import "contracts/staking_module/reliquary/rewarders/RollingRewarder.sol";
import "contracts/staking_module/reliquary/rewarders/ParentRollingRewarder.sol";
import "contracts/staking_module/reliquary/interfaces/ICurves.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

// vault
import {ReaperBaseStrategyv4} from "lib/Cod3x-Vault/src/ReaperBaseStrategyv4.sol";
import {ReaperVaultV2} from "lib/Cod3x-Vault/src/ReaperVaultV2.sol";
import {ScdxUsdVaultStrategy} from "contracts/staking_module/vault_strategy/ScdxUsdVaultStrategy.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract TestStakingModule is TestCdxUSD, ERC721Holder {
    bytes32 public poolId;
    address public poolAdd;
    IERC20[] public assets;
    Reliquary public reliquary;
    RollingRewarder public rewarder;
    ReaperVaultV2 public cod3xVault;
    ScdxUsdVaultStrategy public strategy;

    // Linear function config (to config)
    uint256 public slope = 100; // Increase of multiplier every second
    uint256 public minMultiplier = 365 days * 100; // Arbitrary (but should be coherent with slope)
    uint256 public plateau = 10 days;

    function setUp() public virtual override {
        super.setUp();
        vm.selectFork(forkIdEth);

        /// ======= Balancer Pool Deploy =======
        {
            assets = [IERC20(address(cdxUSD)), usdc, usdt];

            // balancer stable pool creation
            (poolId, poolAdd) = createStablePool(assets, 2500, userA);

            // join Pool
            (IERC20[] memory setupPoolTokens,,) = IVault(vault).getPoolTokens(poolId);
            uint256[] memory amountsToAdd = new uint256[](setupPoolTokens.length);
            amountsToAdd[0] = INITIAL_CDXUSD_AMT;
            amountsToAdd[1] = INITIAL_USDT_AMT;
            amountsToAdd[2] = INITIAL_USDC_AMT;
            amountsToAdd[3] = 0;

            joinPool(poolId, setupPoolTokens, amountsToAdd, userA, JoinKind.INIT);
            vm.prank(userA);
            IERC20(poolAdd).transfer(address(this), 1);
        }

        /// ========= Reliquary Deploy =========
        {
            reliquary = new Reliquary(address(0), 0, "Reliquary scdxUSD", "scdxUSD Relic");
            address linearPlateauCurve =
                address(new LinearPlateauCurve(slope, minMultiplier, plateau));

            address nftDescriptor = address(new NFTDescriptor(address(reliquary)));

            address parentRewarder = address(new ParentRollingRewarder());

            reliquary.grantRole(keccak256("OPERATOR"), address(this));

            console.log(IERC20(poolAdd).totalSupply());
            console.log(IERC20(poolAdd).balanceOf(userA));

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

        /// ========== sdxUSD Vault Strategy Deploy ===========
        {
            address[] memory ownerArr = new address[](3);
            ownerArr[0] = address(this);
            ownerArr[1] = address(this);
            ownerArr[2] = address(this);

            address[] memory ownerArr1 = new address[](1);
            ownerArr[0] = address(this);

            cod3xVault = new ReaperVaultV2(
                poolAdd,
                "Staked Cod3x USD",
                "scdxUSD",
                type(uint256).max,
                0,
                treasury,
                ownerArr,
                ownerArr,
                address(this)
            );

            ScdxUsdVaultStrategy implementation = new ScdxUsdVaultStrategy();
            ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), "");
            strategy = ScdxUsdVaultStrategy(address(proxy));

            reliquary.transferFrom(address(this), address(strategy), 1); // transfer Relic#1 to strategy.
            strategy.initialize(
                address(cod3xVault),
                address(vault),
                ownerArr1,
                ownerArr,
                ownerArr1,
                address(cdxUSD),
                address(reliquary),
                address(poolAdd),
                poolId
            );

            cod3xVault.addStrategy(address(strategy), 0, 100);
        }
    }

    function testInitialBalance() public {
        assertEq(0, usdc.balanceOf(userA));
        assertEq(0, usdt.balanceOf(userA));
        assertEq(0, cdxUSD.balanceOf(userA));
        // assertEq(1e13, IERC20(poolAdd).balanceOf(userA));
    }
}
