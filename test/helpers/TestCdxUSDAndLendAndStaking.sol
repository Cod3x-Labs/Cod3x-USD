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
import {Cod3xLendDataProvider} from "lib/Cod3x-Lend/contracts/misc/Cod3xLendDataProvider.sol";
// import {ReserveBorrowConfiguration} from  "lib/Cod3x-Lend/contracts/protocol/libraries/configuration/ReserveConfiguration.sol";

// Balancer
import {
    IVault,
    JoinKind,
    ExitKind,
    SwapKind
} from "contracts/interfaces/IVault.sol";
import {
    IComposableStablePoolFactory,
    IRateProvider,
    ComposableStablePool
} from "contracts/interfaces/IComposableStablePoolFactory.sol";
import "forge-std/console2.sol";

import {TestCdxUSDAndLend} from "test/helpers/TestCdxUSDAndLend.sol";
import {ERC20Mock} from "test/helpers/mocks/ERC20Mock.sol";

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

contract TestCdxUSDAndLendAndStaking is TestCdxUSDAndLend, ERC721Holder {
    using WadRayMath for uint256;
    // using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    // using ReserveBorrowConfiguration for DataTypes.ReserveBorrowConfigurationMap;

    bytes32 public poolId;
    address public poolAdd;
    IERC20[] public assets;
    IReliquary public reliquary;
    RollingRewarder public rewarder;
    ReaperVaultV2 public cod3xVault;
    ScdxUsdVaultStrategy public strategy;
    IERC20 public mockRewardToken;

    // Linear function config (to config)
    uint256 public slope = 100; // Increase of multiplier every second
    uint256 public minMultiplier = 365 days * 100; // Arbitrary (but should be coherent with slope)
    uint256 public plateauTimestamp = 10 days;
    uint256 private constant RELIC_ID = 1;

    uint256 public indexCdxUsd;
    uint256 public indexCounterAsset;

    // CdxUSD public cdxUsd;
    CdxUsdIInterestRateStrategy public cdxUsdInterestRateStrategy;
    CdxUsdOracle public cdxUsdOracle;
    CdxUsdAToken public cdxUsdAToken;
    CdxUsdVariableDebtToken public cdxUsdVariableDebtToken;
    MockV3Aggregator public counterAssetPriceFeed;

    function setUp() public virtual override {
        super.setUp();
        vm.selectFork(forkIdEth);

        /// ======= Balancer Pool Deploy =======
        {
            assets = [IERC20(address(cdxUsd)), IERC20(address(counterAsset))];

            // balancer stable pool creation
            (poolId, poolAdd) = createStablePool(assets, 2500, userA);

            // join Pool
            (IERC20[] memory setupPoolTokens,,) = IVault(vault).getPoolTokens(poolId);

            uint256 indexCdxUsdTemp;
            uint256 indexCounterAssetTemp;
            uint256 indexBtpTemp;
            for (uint256 i = 0; i < setupPoolTokens.length; i++) {
                if (setupPoolTokens[i] == cdxUsd) indexCdxUsdTemp = i;
                if (setupPoolTokens[i] == IERC20(address(counterAsset))) indexCounterAssetTemp = i;
                if (setupPoolTokens[i] == IERC20(poolAdd)) indexBtpTemp = i;
            }

            uint256[] memory amountsToAdd = new uint256[](setupPoolTokens.length);
            amountsToAdd[indexCdxUsdTemp] = INITIAL_CDXUSD_AMT;
            amountsToAdd[indexCounterAssetTemp] = INITIAL_COUNTER_ASSET_AMT;
            amountsToAdd[indexBtpTemp] = 0;

            joinPool(poolId, setupPoolTokens, amountsToAdd, userA, JoinKind.INIT);

            vm.prank(userA);
            IERC20(poolAdd).transfer(address(this), 1);

            IERC20[] memory setupPoolTokensWithoutBTP =
                BalancerHelper._dropBptItem(setupPoolTokens, poolAdd);

            for (uint256 i = 0; i < setupPoolTokensWithoutBTP.length; i++) {
                if (setupPoolTokensWithoutBTP[i] == cdxUsd) indexCdxUsd = i;
                if (setupPoolTokensWithoutBTP[i] == IERC20(address(counterAsset))) {
                    indexCounterAsset = i;
                }
            }
        }

        /// ========= Reliquary Deploy =========
        {
            mockRewardToken = IERC20(address(new ERC20Mock(18)));
            reliquary =
                new Reliquary(address(mockRewardToken), 0, "Reliquary scdxUSD", "scdxUSD Relic");
            address linearPlateauCurve =
                address(new LinearPlateauCurve(slope, minMultiplier, plateauTimestamp));

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

            rewarder = RollingRewarder(
                ParentRollingRewarder(parentRewarder).createChild(address(cdxUsd))
            );
            IERC20(cdxUsd).approve(address(reliquary), type(uint256).max);
            IERC20(cdxUsd).approve(address(rewarder), type(uint256).max);
        }

        /// ========== scdxUSD Vault Strategy Deploy ===========
        {
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
                treasury,
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
                address(vault),
                ownerArr1,
                ownerArr,
                ownerArr1,
                address(cdxUsd),
                address(reliquary),
                address(poolAdd),
                poolId
            );

            // console2.log(address(cod3xVault));
            // console2.log(address(vault));
            // console2.log(address(cdxUSD));
            // console2.log(address(reliquary));
            // console2.log(address(poolAdd));

            cod3xVault.addStrategy(address(strategy), 0, 10_000); // 100 % invested
        }

        // ======= cdxUSD Cod3x Lend dependencies deploy and configure =======
        {
            cdxUsdAToken = new CdxUsdAToken();
            cdxUsdVariableDebtToken = new CdxUsdVariableDebtToken();
            cdxUsdOracle = new CdxUsdOracle();
            cdxUsdInterestRateStrategy = new CdxUsdIInterestRateStrategy(
                address(deployedContracts.lendingPoolAddressesProvider),
                address(cdxUsd),
                false,
                vault, // balancerVault,
                poolId,
                1e25,
                2e25, // starts at 2% interest rate
                13e19
            );
            counterAssetPriceFeed =
                new MockV3Aggregator(PRICE_FEED_DECIMALS, int256(1 * 10 ** PRICE_FEED_DECIMALS));
            cdxUsdInterestRateStrategy.setOracleValues(
                address(counterAssetPriceFeed), 1e26, /* 10% */ 86400
            );


            fixture_configureCdxUsd(
                address(deployedContracts.lendingPool),
                address(cdxUsdAToken),
                address(cdxUsdVariableDebtToken),
                address(cdxUsdOracle),
                address(cdxUsd),
                address(cdxUsdInterestRateStrategy),
                address(rewarder),
                configAddresses,
                deployedContracts.lendingPoolConfigurator,
                deployedContracts.lendingPoolAddressesProvider
            );

            cdxUsd.addFacilitator(
                deployedContracts.lendingPool.getReserveData(address(cdxUsd), false).aTokenAddress,
                "Cod3x Lend",
                DEFAULT_CAPACITY
            );
            // configAddresses = ConfigAddresses(
            //     address(deployedContracts.cod3xLendDataProvider),
            //     address(deployedContracts.stableStrategy),
            //     address(deployedContracts.volatileStrategy),
            //     address(deployedContracts.treasury),
            //     address(deployedContracts.rewarder),
            //     address(deployedContracts.aTokensAndRatesHelper)
            // );

            tokens.push(address(cdxUsd));
            commonContracts.aTokens =
                fixture_getATokens(tokens, Cod3xLendDataProvider(configAddresses.cod3xLendDataProvider));

            erc20Tokens.push(ERC20(address(cdxUsd)));
            // console2.log("Index: ", idx);
            (address _aTokenAddress,) = deployedContracts
                .protocolDataProvider
                .getReserveTokensAddresses(address(cdxUsd), false);
            aTokens.push(AToken(_aTokenAddress));
            (, address _variableDebtToken) = deployedContracts
                .protocolDataProvider
                .getReserveTokensAddresses(address(cdxUsd), false);
            variableDebtTokens.push(VariableDebtToken(_variableDebtToken));
        }

        // MAX approve "cod3xVault" by all users
        for (uint160 i = 1; i <= 3; i++) {
            vm.prank(address(i)); // address(0x1) == address(1)
            IERC20(poolAdd).approve(address(cod3xVault), type(uint256).max);
        }
    }
}
