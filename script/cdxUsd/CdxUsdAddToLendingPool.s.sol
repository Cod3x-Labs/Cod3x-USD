// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {Test} from "forge-std/Test.sol";
import "contracts/tokens/CdxUSD.sol";
import {CdxUsdAToken} from "contracts/facilitators/cod3x_lend/token/CdxUsdAToken.sol";
import {CdxUsdVariableDebtToken} from
    "contracts/facilitators/cod3x_lend/token/CdxUsdVariableDebtToken.sol";

import "contracts/staking_module/reliquary/Reliquary.sol";
import "contracts/staking_module/reliquary/curves/LinearPlateauCurve.sol";
import "contracts/staking_module/reliquary/rewarders/RollingRewarder.sol";
import "contracts/staking_module/reliquary/rewarders/ParentRollingRewarder.sol";
import "contracts/staking_module/reliquary/nft_descriptors/NFTDescriptor.sol";
import "lib/Cod3x-Vault/test/vault/mock/FeeControllerMock.sol";
import {ReaperVaultV2} from "lib/Cod3x-Vault/src/ReaperVaultV2.sol";
import {ScdxUsdVaultStrategy} from
    "contracts/staking_module/vault_strategy/ScdxUsdVaultStrategy.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IVaultExplorer} from
    "lib/balancer-v3-monorepo/pkg/interfaces/contracts/vault/IVaultExplorer.sol";
import {TRouter} from "test/helpers/TRouter.sol";
import "test/helpers/TestCdxUSDAndLend.sol";
import {CdxUsdIInterestRateStrategy} from
    "contracts/facilitators/cod3x_lend/interest_strategy/CdxUsdIInterestRateStrategy.sol";
import {CdxUsdOracle} from "contracts/facilitators/cod3x_lend/oracle/CdxUSDOracle.sol";
import {Oracle} from "lib/Cod3x-Lend/contracts/protocol/core/Oracle.sol";

//Temporary
import {console2} from "forge-std/console2.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {ERC20Mock} from "test/helpers/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "test/helpers/mocks/MockV3Aggregator.sol";

contract CdxUsdAddToLendingPool is Script, Test, TestCdxUSDAndLend {
    struct ReliquaryParams {
        uint256 slope; // Increase of multiplier every second
        uint256 minMultiplier; // Arbitrary (but should be coherent with slope)
        uint256 plateau;
    }

    struct ContractsToDeploy {
        address stablePool;
        Reliquary reliquary;
        RollingRewarder rewarder;
        BalancerV3Router balancerV3Router;
        ReaperVaultV2 cod3xVault;
        ScdxUsdVaultStrategy strategy;
        CdxUsdAToken cdxUsdAToken;
        CdxUsdVariableDebtToken cdxUsdVariableDebtToken;
        CdxUsdOracle cdxUsdAggregator;
    }

    function setUp() public override {}

    function run() public {
        address user1 = makeAddr("user1");
        string memory BASE_RPC_URL = vm.envString("BASE_RPC_URL");
        vm.createSelectFork(BASE_RPC_URL);
        deal(cdxUsd, user1, 100_000e18);
        deal(BASE_USDC, user1, 100_000e18);
        // vm.broadcast();
        vm.startPrank(user1);
        /// Variables
        ContractsToDeploy memory contractsToDeploy;

        /// ========= Balancer pool Deploy =========
        {
            console2.log("====== Stable Pool Deployment ======");
            TRouter tRouter = new TRouter();
            uint256 initialCdxAmt = 100_000e18;
            uint256 initialCounterAssetAmt = 100_000e6;

            IERC20[] memory assets = new IERC20[](2);
            assets[0] = IERC20(cdxUsd);
            assets[1] = IERC20(BASE_USDC);
            assets = sort(assets);
            contractsToDeploy.stablePool = createStablePool(assets, 2500, address(this));
            IERC20[] memory setupPoolTokens = IVaultExplorer(balancerContracts.balVault)
                .getPoolTokens(contractsToDeploy.stablePool);
            uint256 indexCdxUsdTemp;
            uint256 indexCounterAssetTemp;

            for (uint256 i = 0; i < setupPoolTokens.length; i++) {
                console2.log("setupPoolTokens[i]: ", address(setupPoolTokens[i]));
                if (setupPoolTokens[i] == IERC20(cdxUsd)) indexCdxUsdTemp = i;
                if (setupPoolTokens[i] == IERC20(BASE_USDC)) indexCounterAssetTemp = i;
            }

            uint256[] memory amountsToAdd = new uint256[](setupPoolTokens.length);
            amountsToAdd[indexCdxUsdTemp] = initialCdxAmt;
            amountsToAdd[indexCounterAssetTemp] = initialCounterAssetAmt;

            IERC20(cdxUsd).approve(address(tRouter), type(uint256).max);
            IERC20(BASE_USDC).approve(address(tRouter), type(uint256).max);
            tRouter.initialize(contractsToDeploy.stablePool, assets, amountsToAdd);

            IERC20(contractsToDeploy.stablePool).transfer(address(this), 1);
        }

        /// ========= Reliquary Deploy =========
        {
            uint256 SLOPE = 100;
            uint256 MIN_MULTIPLIER = 365 days * 100;
            uint256 PLATEAU = 10 days;
            address REWARD_TOKEN = address(new ERC20Mock(18));

            console2.log("====== Reliquary Deployment ======");
            contractsToDeploy.reliquary =
                new Reliquary(REWARD_TOKEN, 0, "Reliquary scdxUsd", "scdxUsd Relic");
            address linearPlateauCurve =
                address(new LinearPlateauCurve(SLOPE, MIN_MULTIPLIER, PLATEAU));

            address nftDescriptor = address(new NFTDescriptor(address(contractsToDeploy.reliquary)));
            address parentRewarder = address(new ParentRollingRewarder());
            Reliquary(address(contractsToDeploy.reliquary)).grantRole(
                keccak256("OPERATOR"), address(this)
            );
            Reliquary(address(contractsToDeploy.reliquary)).grantRole(
                keccak256("GUARDIAN"), address(this)
            );
            Reliquary(address(contractsToDeploy.reliquary)).grantRole(
                keccak256("EMISSION_RATE"), address(this)
            );

            console2.log("====== Adding Pool to Reliquary ======");
            IERC20(contractsToDeploy.stablePool).approve(address(contractsToDeploy.reliquary), 1); // approve 1 wei to bootstrap the pool
            contractsToDeploy.reliquary.addPool(
                100, // alloc point - only one pool is necessary
                address(contractsToDeploy.stablePool), // BTP
                address(parentRewarder),
                ICurves(linearPlateauCurve),
                "scdxUsd Pool",
                nftDescriptor,
                true, // allowPartialWithdrawals
                user1 // can send to the strategy directly.
            );

            contractsToDeploy.rewarder =
                RollingRewarder(ParentRollingRewarder(parentRewarder).createChild(address(cdxUsd)));
            IERC20(cdxUsd).approve(address(contractsToDeploy.reliquary), type(uint256).max);
            IERC20(cdxUsd).approve(address(contractsToDeploy.rewarder), type(uint256).max);
        }

        /// ========== scdxUsd Vault Strategy Deploy ===========
        uint256 RELIC_ID = 1;
        address FEE_CONTROLLER = address(new FeeControllerMock());
        {
            console2.log("====== scdxUsd Vault Strategy Deployment ======");
            address[] memory interactors = new address[](1);
            interactors[0] = address(this);
            contractsToDeploy.balancerV3Router =
                new BalancerV3Router(address(balancerContracts.balVault), user1, interactors);

            address[] memory ownerArr = new address[](3);
            ownerArr[0] = address(this);
            ownerArr[1] = address(this);
            ownerArr[2] = address(this);

            address[] memory ownerArr1 = new address[](1);
            ownerArr[0] = address(this);
            {
                IFeeController(FEE_CONTROLLER).updateManagementFeeBPS(0);

                contractsToDeploy.cod3xVault = new ReaperVaultV2(
                    contractsToDeploy.stablePool,
                    "Staked Cod3x USD",
                    "scdxUsd",
                    type(uint256).max,
                    0,
                    extContracts.treasury,
                    ownerArr,
                    ownerArr,
                    FEE_CONTROLLER
                );
            }

            {
                ScdxUsdVaultStrategy implementation = new ScdxUsdVaultStrategy();
                ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), "");
                contractsToDeploy.strategy = ScdxUsdVaultStrategy(address(proxy));
            }
            contractsToDeploy.reliquary.transferFrom(
                user1, address(contractsToDeploy.strategy), RELIC_ID
            ); // transfer Relic#1 to strategy.
            contractsToDeploy.strategy.initialize(
                address(contractsToDeploy.cod3xVault),
                address(balancerContracts.balVault),
                address(contractsToDeploy.balancerV3Router),
                ownerArr1,
                ownerArr,
                ownerArr1,
                address(cdxUsd),
                address(contractsToDeploy.reliquary),
                address(contractsToDeploy.stablePool)
            );

            // console2.log(address(cod3xVault));
            // console2.log(address(vaultV3));
            // console2.log(address(cdxUsd));
            // console2.log(address(reliquary));
            // console2.log(address(poolAdd));

            contractsToDeploy.cod3xVault.addStrategy(address(contractsToDeploy.strategy), 0, 10_000); // 100 % invested

            //DEFAULT AMIND ROLE - balancer team shall do it
            address[] memory interactors2 = new address[](1);
            interactors2[0] = address(contractsToDeploy.strategy);
            contractsToDeploy.balancerV3Router.setInteractors(interactors2);
        }

        PoolReserversConfig memory poolReserversConfig =
            PoolReserversConfig({borrowingEnabled: true, reserveFactor: 1000, reserveType: false});

        /// ========= aTokens Deploy =========
        {
            contractsToDeploy.cdxUsdAToken = new CdxUsdAToken();
            contractsToDeploy.cdxUsdVariableDebtToken = new CdxUsdVariableDebtToken();
        }

        /// ========= Interest strat Deploy =========
        CdxUsdIInterestRateStrategy cdxUsdInterestRateStrategy;
        {
            int256 MIN_CONTROLLER_ERROR = 1e25;
            int256 INITIAL_ERR_I_VALUE = 1e25;
            uint256 KI = 13e19;

            cdxUsdInterestRateStrategy = new CdxUsdIInterestRateStrategy(
                extContracts.lendingPoolAddressesProvider,
                address(cdxUsd),
                false, // Not used
                address(balancerContracts.balVault), // balancerVault,
                address(contractsToDeploy.stablePool),
                MIN_CONTROLLER_ERROR,
                INITIAL_ERR_I_VALUE, // starts at 2% interest rate
                KI
            );
        }
        uint256 ORACLE_TIMEOUT = 86400; // 1 day
        /// ========= Oracle Deploy =========
        {
            uint256 PEG_MARGIN = 1e26; // 10%

            contractsToDeploy.cdxUsdAggregator = new CdxUsdOracle();
            MockV3Aggregator counterAssetPriceFeed =
                new MockV3Aggregator(PRICE_FEED_DECIMALS, int256(1 * 10 ** PRICE_FEED_DECIMALS));
            vm.startPrank(deployer);
            cdxUsdInterestRateStrategy.setOracleValues(
                address(counterAssetPriceFeed), PEG_MARGIN, ORACLE_TIMEOUT
            );
            vm.stopPrank();
        }

        /// ========= Init cod3xUsd on cod3x lend =========
        console2.log("====== Init cod3xUsd on cod3x lend ======");
        ILendingPool lendingPool = ILendingPool(
            ILendingPoolAddressesProvider(extContracts.lendingPoolAddressesProvider).getLendingPool(
            )
        );
        {
            uint256 RELIQUARY_ALLOCATION = 8000; /* 80% */

            ExtContractsForConfiguration memory extContractsForConfiguration =
            ExtContractsForConfiguration({
                treasury: multisignAdmin,
                rewarder: extContracts.rewarder,
                oracle: extContracts.oracle,
                lendingPoolConfigurator: extContracts.lendingPoolConfigurator,
                lendingPoolAddressesProvider: extContracts.lendingPoolAddressesProvider,
                aTokenImpl: address(contractsToDeploy.cdxUsdAToken),
                variableDebtTokenImpl: address(contractsToDeploy.cdxUsdVariableDebtToken),
                interestStrat: address(cdxUsdInterestRateStrategy)
            });
            vm.stopPrank();
            console2.log("=== cdxUsd configuration ===");
            fixture_configureCdxUsd(
                extContractsForConfiguration,
                poolReserversConfig,
                cdxUsd,
                address(contractsToDeploy.reliquary),
                address(contractsToDeploy.cdxUsdAggregator),
                RELIQUARY_ALLOCATION,
                ORACLE_TIMEOUT,
                deployer
            );
            // fixture_configureReservesCdxUsd(
            //     extContractsForConfiguration, poolReserversConfig, cdxUsd, deployer
            // );

            /// CdxUsdAToken settings
            // contractsToDeploy.cdxUsdAToken.setVariableDebtToken(
            //     address(contractsToDeploy.cdxUsdVariableDebtToken)
            // );
            // ILendingPoolConfigurator(extContracts.lendingPoolConfigurator).setTreasury(
            //     address(cdxUsd), poolReserversConfig.reserveType, extContracts.treasury
            // );
            // contractsToDeploy.cdxUsdAToken.setReliquaryInfo(
            //     address(contractsToDeploy.reliquary), RELIQUARY_ALLOCATION
            // );
            // contractsToDeploy.cdxUsdAToken.setKeeper(address(this));

            // /// CdxUsdVariableDebtToken settings
            // contractsToDeploy.cdxUsdVariableDebtToken.setAToken(
            //     address(contractsToDeploy.cdxUsdAToken)
            // );
            console2.log("=== Adding Facilitator ===");
            DataTypes.ReserveData memory reserveData =
                lendingPool.getReserveData(cdxUsd, poolReserversConfig.reserveType);
            vm.prank(CdxUSD(cdxUsd).owner());
            CdxUSD(cdxUsd).addFacilitator(reserveData.aTokenAddress, "aToken", 100_000e18);
        }

        console2.log("====== Testing ======");
        {
            vm.startPrank(user1);
            uint256 amountToDeposit = 2000e6;
            uint256 amountToBorrow = 1000e18;

            // Deposit
            IERC20(BASE_USDC).approve(address(lendingPool), type(uint256).max);
            lendingPool.deposit(BASE_USDC, poolReserversConfig.reserveType, amountToDeposit, user1);

            // Borrow
            lendingPool.borrow(cdxUsd, poolReserversConfig.reserveType, amountToBorrow, user1);

            assertEq(
                IERC20(cdxUsd).balanceOf(user1), amountToBorrow, "User1 should have borrowed cdxUsd"
            );

            // Repay
            IERC20(cdxUsd).approve(address(lendingPool), type(uint256).max);
            lendingPool.repay(cdxUsd, poolReserversConfig.reserveType, amountToBorrow, user1);

            assertEq(IERC20(cdxUsd).balanceOf(user1), 0, "User1 should have repaid cdxUsd");
        }
    }
}
