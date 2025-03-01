// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

// Cod3x Lend
import {ERC20} from "lib/Cod3x-Lend/contracts/dependencies/openzeppelin/contracts/ERC20.sol";
import {Rewarder} from "lib/Cod3x-Lend/contracts/protocol/rewarder/lendingpool/Rewarder.sol";
import {Oracle} from "lib/Cod3x-Lend/contracts/protocol/core/Oracle.sol";
import {Treasury} from "lib/Cod3x-Lend/contracts/misc/Treasury.sol";
import {WETHGateway} from "lib/Cod3x-Lend/contracts/misc/WETHGateway.sol";
import {ReserveLogic} from
    "lib/Cod3x-Lend/contracts/protocol/core/lendingpool/logic/ReserveLogic.sol";
import {GenericLogic} from
    "lib/Cod3x-Lend/contracts/protocol/core/lendingpool/logic/GenericLogic.sol";
import {ValidationLogic} from
    "lib/Cod3x-Lend/contracts/protocol/core/lendingpool/logic/ValidationLogic.sol";
import {LendingPoolAddressesProvider} from
    "lib/Cod3x-Lend/contracts/protocol/configuration/LendingPoolAddressesProvider.sol";
import {DefaultReserveInterestRateStrategy} from
    "lib/Cod3x-Lend/contracts/protocol/core/interestRateStrategies/lendingpool/DefaultReserveInterestRateStrategy.sol";
import {PiReserveInterestRateStrategy} from
    "lib/Cod3x-Lend/contracts/protocol/core/interestRateStrategies/lendingpool/PiReserveInterestRateStrategy.sol";
import {MiniPoolPiReserveInterestRateStrategy} from
    "lib/Cod3x-Lend/contracts/protocol/core/interestRateStrategies/minipool/MiniPoolPiReserveInterestRateStrategy.sol";
import {LendingPool} from "lib/Cod3x-Lend/contracts/protocol/core/lendingpool/LendingPool.sol";
import {LendingPoolConfigurator} from
    "lib/Cod3x-Lend/contracts/protocol/core/lendingpool/LendingPoolConfigurator.sol";
import {MiniPool} from "lib/Cod3x-Lend/contracts/protocol/core/minipool/MiniPool.sol";
import {MiniPoolAddressesProvider} from
    "lib/Cod3x-Lend/contracts/protocol/configuration/MiniPoolAddressProvider.sol";
import {MiniPoolConfigurator} from
    "lib/Cod3x-Lend/contracts/protocol/core/minipool/MiniPoolConfigurator.sol";
import {FlowLimiter} from "lib/Cod3x-Lend/contracts/protocol/core/minipool/FlowLimiter.sol";
import {ATokensAndRatesHelper} from "lib/Cod3x-Lend/contracts/deployments/ATokensAndRatesHelper.sol";
import {AToken} from "lib/Cod3x-Lend/contracts/protocol/tokenization/ERC20/AToken.sol";
import {ATokenERC6909} from
    "lib/Cod3x-Lend/contracts/protocol/tokenization/ERC6909/ATokenERC6909.sol";
import {VariableDebtToken} from
    "lib/Cod3x-Lend/contracts/protocol/tokenization/ERC20/VariableDebtToken.sol";
import {MintableERC20} from "lib/Cod3x-Lend/contracts/mocks/tokens/MintableERC20.sol";
import {WETH9Mocked} from "lib/Cod3x-Lend/contracts/mocks/tokens/WETH9Mocked.sol";
import {MockAggregator} from "lib/Cod3x-Lend/contracts/mocks/oracle/MockAggregator.sol";
import {MockReaperVault2} from "lib/Cod3x-Lend/contracts/mocks/tokens/MockVault.sol";
import {ExternalContract} from "lib/Cod3x-Lend/contracts/mocks/tokens/ExternalContract.sol";
import {IStrategy} from "lib/Cod3x-Lend/contracts/mocks/dependencies/IStrategy.sol";
import {IExternalContract} from "lib/Cod3x-Lend/contracts/mocks/dependencies/IExternalContract.sol";
import {WadRayMath} from "lib/Cod3x-Lend/contracts/protocol/libraries/math/WadRayMath.sol";
import {MiniPoolDefaultReserveInterestRateStrategy} from
    "lib/Cod3x-Lend/contracts/protocol/core/interestRateStrategies/minipool/MiniPoolDefaultReserveInterestRate.sol";
import {PriceOracle} from "lib/Cod3x-Lend/contracts/mocks/oracle/PriceOracle.sol";
import {ILendingPoolConfigurator} from
    "lib/Cod3x-Lend/contracts/interfaces/ILendingPoolConfigurator.sol";
import "lib/Cod3x-Lend/contracts/interfaces/ILendingPoolAddressesProvider.sol";
import "lib/Cod3x-Lend/contracts/interfaces/IMiniPoolConfigurator.sol";
import {IMiniPool} from "lib/Cod3x-Lend/contracts/interfaces/IMiniPool.sol";
import {IMiniPoolAddressesProvider} from
    "lib/Cod3x-Lend/contracts/interfaces/IMiniPoolAddressesProvider.sol";
import {ILendingPool} from "lib/Cod3x-Lend/contracts/interfaces/ILendingPool.sol";
import {DataTypes} from "lib/Cod3x-Lend/contracts/protocol/libraries/types/DataTypes.sol";
import {Cod3xLendDataProvider} from "lib/Cod3x-Lend/contracts/misc/Cod3xLendDataProvider.sol";
import {MockVaultUnit} from "lib/Cod3x-Lend/contracts/mocks/tokens/MockVaultUnit.sol";
import {ProtocolDataProvider} from "test/helpers/ProtocolDataProvider.sol";

// Mock imports
import {OFTMock} from "../helpers/mocks/OFTMock.sol";
import {ERC20Mock} from "../helpers/mocks/ERC20Mock.sol";
import {OFTComposerMock} from "../helpers/mocks/OFTComposerMock.sol";
import {IOFTExtended} from "contracts/interfaces/IOFTExtended.sol";

// OApp imports
import {
    IOAppOptionsType3,
    EnforcedOptionParam
} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OAppOptionsType3.sol";
import {OptionsBuilder} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";

// OFT imports
import {
    IOFT,
    SendParam,
    OFTReceipt
} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";
import {
    MessagingFee, MessagingReceipt
} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFTCore.sol";
import {OFTMsgCodec} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/libs/OFTMsgCodec.sol";
import {OFTComposeMsgCodec} from
    "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/libs/OFTComposeMsgCodec.sol";

// DevTools imports
import {TestHelperOz5} from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";

/// Main import
import "@openzeppelin/contracts/utils/Strings.sol";
import "contracts/tokens/CdxUSD.sol";
import "contracts/interfaces/ICdxUSD.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import "test/helpers/Events.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import "test/helpers/Constants.sol";
import "test/helpers/Sort.sol";
import {
    IComposableStablePoolFactory,
    IRateProvider,
    ComposableStablePool
} from "contracts/interfaces/IComposableStablePoolFactory.sol";
import {IAsset} from "node_modules/@balancer-labs/v2-interfaces/contracts/vault/IAsset.sol";
import {
    IVault,
    JoinKind,
    ExitKind,
    SwapKind
} from "contracts/interfaces/IVault.sol";
import {CdxUsdAToken} from "contracts/facilitators/cod3x_lend/token/CdxUsdAToken.sol";
import {CdxUsdVariableDebtToken} from
    "contracts/facilitators/cod3x_lend/token/CdxUsdVariableDebtToken.sol";

import "contracts/staking_module/reliquary/rewarders/RollingRewarder.sol";

import "forge-std/console2.sol";

contract TestCdxUSDAndLend is TestHelperOz5, Sort, Events, Constants {
    using WadRayMath for uint256;

    uint32 aEid = 1;
    uint32 bEid = 2;
    uint256 public forkIdEth;

    address[] public tokens; // = [wbtc, weth, dai];
    ERC20[] erc20Tokens;
    DeployedContracts deployedContracts;
    ConfigAddresses configAddresses;

    uint256[] public rates = [0.039e27, 0.03e27, 0.03e27]; // = [wbtc, weth, dai, cdxUsd];
    uint256[] public volStrat = [
        VOLATILE_OPTIMAL_UTILIZATION_RATE,
        VOLATILE_BASE_VARIABLE_BORROW_RATE,
        VOLATILE_VARIABLE_RATE_SLOPE_1,
        VOLATILE_VARIABLE_RATE_SLOPE_2
    ]; // optimalUtilizationRate, baseVariableBorrowRate, variableRateSlope1, variableRateSlope2
    uint256[] public sStrat = [
        STABLE_OPTIMAL_UTILIZATION_RATE,
        STABLE_BASE_VARIABLE_BORROW_RATE,
        STABLE_VARIABLE_RATE_SLOPE_1,
        STABLE_VARIABLE_RATE_SLOPE_2
    ]; // optimalUtilizationRate, baseVariableBorrowRate, variableRateSlope1, variableRateSlope2
    bool[] public isStableStrategy = [false, false, true];
    bool[] public reserveTypes = [true, true, true];

    // Protocol deployment variables
    uint256 providerId = 1;
    string marketId = "Cod3x Lend Genesis Market";
    uint256 cntr;

    address constant ETH_USD_SOURCE = 0xb7B9A39CC63f856b90B364911CC324dC46aC1770;
    address constant USDC_USD_SOURCE = 0x16a9FA2FDa030272Ce99B29CF780dFA30361E0f3;

    address public userA = address(0x1);
    address public userB = address(0x2);
    address public userC = address(0x3);
    address public owner = address(this);
    address public guardian = address(0x4);
    address public treasury = address(0x5);

    CdxUSD public cdxUsd;
    ERC20 public counterAsset;

    address[] public aggregators;

    address public reserveLogic;
    address public genericLogic;
    address public validationLogic;

    // StableAndVariableTokensHelper public stableAndVariableTokensHelper;
    Oracle public oracle;

    WETHGateway public wETHGateway;
    AToken public aToken;
    VariableDebtToken public variableDebtToken;
    ATokenERC6909 public aTokenErc6909;

    AToken[] public aTokens;
    VariableDebtToken[] public variableDebtTokens;
    ATokenERC6909[] public aTokensErc6909;

    MockReaperVault2[] public mockedVaults;

    uint128 public constant DEFAULT_CAPACITY = 100_000_000e18;
    uint128 public constant INITIAL_CDXUSD_AMT = 10_000_000e18;
    uint128 public constant INITIAL_COUNTER_ASSET_AMT = 10_000_000e18;
    uint128 public constant INITIAL_AMT = 100_000 ether;

    address public constant ZERO_ADDRESS = address(0);
    address public constant BASE_CURRENCY = address(0);
    uint256 public constant BASE_CURRENCY_UNIT = 100000000;
    address public constant FALLBACK_ORACLE = address(0);
    uint256 public constant TVL_CAP = 1e20;
    uint256 public constant PERCENTAGE_FACTOR = 10_000;
    uint8 public constant PRICE_FEED_DECIMALS = 8;
    uint8 public constant RAY_DECIMALS = 27;

    /* Utilization rate targeted by the model, beyond the variable interest rate rises sharply */
    uint256 constant VOLATILE_OPTIMAL_UTILIZATION_RATE = 0.45e27;
    uint256 constant STABLE_OPTIMAL_UTILIZATION_RATE = 0.8e27;

    /* Constant rates when total borrow is 0 */
    uint256 constant VOLATILE_BASE_VARIABLE_BORROW_RATE = 0e27;
    uint256 constant STABLE_BASE_VARIABLE_BORROW_RATE = 0e27;

    /* Constant rates reprezenting scaling of the interest rate */
    uint256 constant VOLATILE_VARIABLE_RATE_SLOPE_1 = 0.07e27;
    uint256 constant STABLE_VARIABLE_RATE_SLOPE_1 = 0.04e27;
    uint256 constant VOLATILE_VARIABLE_RATE_SLOPE_2 = 3e27;
    uint256 constant STABLE_VARIABLE_RATE_SLOPE_2 = 0.75e27;
    CommonContracts public commonContracts;

    // Structures
    struct ReserveDataParams {
        uint256 availableLiquidity;
        uint256 totalVariableDebt;
        uint256 liquidityRate;
        uint256 variableBorrowRate;
        uint256 liquidityIndex;
        uint256 variableBorrowIndex;
        uint40 lastUpdateTimestamp;
    }

    struct TokenTypes {
        ERC20 token;
        AToken aToken;
        VariableDebtToken debtToken;
    }

    struct ConfigAddresses {
        address cod3xLendDataProvider;
        address stableStrategy;
        address volatileStrategy;
        address treasury;
        address rewarder;
        address aTokensAndRatesHelper;
    }

    struct PidConfig {
        address asset;
        bool assetReserveType;
        int256 minControllerError;
        int256 maxITimeAmp;
        uint256 optimalUtilizationRate;
        uint256 kp;
        uint256 ki;
    }

    struct DeployedContracts {
        Rewarder rewarder;
        LendingPoolAddressesProvider lendingPoolAddressesProvider;
        LendingPool lendingPool;
        Treasury treasury;
        LendingPoolConfigurator lendingPoolConfigurator;
        DefaultReserveInterestRateStrategy stableStrategy;
        DefaultReserveInterestRateStrategy volatileStrategy;
        PiReserveInterestRateStrategy piStrategy;
        Cod3xLendDataProvider cod3xLendDataProvider;
        ProtocolDataProvider protocolDataProvider;
        ATokensAndRatesHelper aTokensAndRatesHelper;
    }

    struct DeployedMiniPoolContracts {
        MiniPool miniPoolImpl;
        MiniPoolAddressesProvider miniPoolAddressesProvider;
        MiniPoolConfigurator miniPoolConfigurator;
        MiniPoolDefaultReserveInterestRateStrategy stableStrategy;
        MiniPoolDefaultReserveInterestRateStrategy volatileStrategy;
        MiniPoolPiReserveInterestRateStrategy piStrategy;
        ATokenERC6909 aToken6909Impl;
        FlowLimiter flowLimiter;
    }

    struct TokenParams {
        ERC20 token;
        AToken aToken;
        uint256 price;
    }

    struct TokenParamsExtended {
        ERC20 token;
        AToken aToken;
        AToken aTokenWrapper;
        MockVaultUnit vault;
        uint256 price;
    }

    struct CommonContracts {
        address[] aggregators;
        address[] aggregatorsPyth;
        Oracle oracle;
        Oracle oraclePyth;
        WETHGateway wETHGateway;
        AToken aToken;
        VariableDebtToken variableDebtToken;
        ATokenERC6909 aTokenErc6909;
        AToken[] aTokens;
        AToken[] aTokensWrapper;
        VariableDebtToken[] variableDebtTokens;
        ATokenERC6909[] aTokensErc6909;
        MockReaperVault2[] mockedVaults;
        MockVaultUnit[] mockVaultUnits;
        PidConfig defaultPidConfig;
    }

    function setUp() public virtual override {
        super.setUp();

        string memory MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");
        forkIdEth = vm.createFork(MAINNET_RPC_URL, 20219106);

        uint128 INITIAL_ETH_MINT = 1000 ether;

        vm.deal(userA, INITIAL_ETH_MINT);
        vm.deal(userB, INITIAL_ETH_MINT);
        vm.deal(userC, INITIAL_ETH_MINT);

        /// ======= cdxUSD deploy =======
        {
            setUpEndpoints(2, LibraryType.UltraLightNode);
            cdxUsd = CdxUSD(
                _deployOApp(
                    type(CdxUSD).creationCode,
                    abi.encode("aOFT", "aOFT", address(endpoints[aEid]), owner, treasury, guardian)
                )
            );
            cdxUsd.addFacilitator(userA, "user a", DEFAULT_CAPACITY);
        }

        /// ======= Counter Asset deployments =======
        {
            counterAsset = ERC20(address(new ERC20Mock(18)));

            weth = address(new ERC20Mock(18));
            wbtc = address(new ERC20Mock(8));
            dai = address(new ERC20Mock(18));
            tokens.push(wbtc);
            tokens.push(weth);
            tokens.push(dai);

            /// initial mint
            ERC20Mock(address(counterAsset)).mint(userA, INITIAL_COUNTER_ASSET_AMT);
            ERC20Mock(address(counterAsset)).mint(userB, INITIAL_COUNTER_ASSET_AMT);
            ERC20Mock(address(counterAsset)).mint(userC, INITIAL_COUNTER_ASSET_AMT);
        }

        /// ======= Cod3x Lend deploy =======
        {
            deployedContracts = fixture_deployProtocol();
            configAddresses = ConfigAddresses(
                address(deployedContracts.cod3xLendDataProvider),
                address(deployedContracts.stableStrategy),
                address(deployedContracts.volatileStrategy),
                address(deployedContracts.treasury),
                address(deployedContracts.rewarder),
                address(deployedContracts.aTokensAndRatesHelper)
            );
            fixture_configureProtocol(
                address(deployedContracts.lendingPool),
                address(commonContracts.aToken),
                configAddresses,
                deployedContracts.lendingPoolConfigurator,
                deployedContracts.lendingPoolAddressesProvider
            );
            // mockedVaults = fixture_deployErc4626Mocks(tokens, address(deployedContracts.treasury));
            erc20Tokens = fixture_getErc20Tokens(tokens);
            fixture_transferTokensToTestContract(erc20Tokens, INITIAL_AMT, address(this));
        }

        deployedContracts.protocolDataProvider = new ProtocolDataProvider(
            deployedContracts.lendingPoolAddressesProvider
        );

        /// ======= Faucet and Approve =======
        {
            vm.startPrank(userA);
            cdxUsd.mint(userA, INITIAL_CDXUSD_AMT);
            cdxUsd.mint(userB, INITIAL_CDXUSD_AMT);
            cdxUsd.mint(address(this), INITIAL_CDXUSD_AMT);
            vm.stopPrank();

            ERC20Mock(address(counterAsset)).mint(userB, INITIAL_COUNTER_ASSET_AMT);

            // MAX approve "vault" by all users
            for (uint160 i = 1; i <= 3; i++) {
                vm.startPrank(address(i)); // address(0x1) == address(1)
                cdxUsd.approve(vault, type(uint256).max);
                counterAsset.approve(vault, type(uint256).max);
                vm.stopPrank();
            }
        }
    }

    // ======= Cod3x USD =======

    function fixture_configureCdxUsd(
        address _lendingPool,
        address _aToken,
        address _variableDebtToken,
        address _cdxUsdOracle,
        address _cdxUsd,
        address _interestStrategy,
        address _reliquaryCdxusdRewarder,
        ConfigAddresses memory configAddresses,
        LendingPoolConfigurator lendingPoolConfiguratorProxy,
        LendingPoolAddressesProvider lendingPoolAddressesProvider
    ) public {
        address[] memory asset = new address[](1);
        address[] memory aggregator = new address[](1);
        uint256[] memory timeout = new uint256[](1);

        asset[0] = _cdxUsd;
        aggregator[0] = _cdxUsdOracle;
        timeout[0] = 1000 days;

        commonContracts.oracle.setAssetSources(asset, aggregator, timeout);

        fixture_configureReservesCdxUsd(
            configAddresses,
            lendingPoolConfiguratorProxy,
            lendingPoolAddressesProvider,
            _aToken,
            _variableDebtToken,
            _cdxUsd,
            _interestStrategy
        );

        DataTypes.ReserveData memory reserveDataTemp =
            deployedContracts.lendingPool.getReserveData(_cdxUsd, false);
        CdxUsdAToken(reserveDataTemp.aTokenAddress).setVariableDebtToken(
            reserveDataTemp.variableDebtTokenAddress
        );
        deployedContracts.lendingPoolConfigurator.setTreasury(address(cdxUsd), false, treasury);
        CdxUsdAToken(reserveDataTemp.aTokenAddress).setReliquaryInfo(
            _reliquaryCdxusdRewarder, 8000 /* 80% */
        );
        CdxUsdAToken(reserveDataTemp.aTokenAddress).setKeeper(address(this));
        DataTypes.ReserveData memory reserve =
            ILendingPool(_lendingPool).getReserveData(_cdxUsd, false);

        CdxUsdVariableDebtToken(reserveDataTemp.variableDebtTokenAddress).setAToken(
            reserveDataTemp.aTokenAddress
        );
    }

    function fixture_configureReservesCdxUsd(
        ConfigAddresses memory configAddresses,
        LendingPoolConfigurator lendingPoolConfigurator,
        LendingPoolAddressesProvider lendingPoolAddressesProvider,
        address _aTokenAddress,
        address _variableDebtToken,
        address _cdxUsd,
        address _interestStrategy
    ) public {
        ILendingPoolConfigurator.InitReserveInput[] memory initInputParams =
            new ILendingPoolConfigurator.InitReserveInput[](1);
        ATokensAndRatesHelper.ConfigureReserveInput[] memory inputConfigParams =
            new ATokensAndRatesHelper.ConfigureReserveInput[](1);

        string memory tmpSymbol = ERC20(_cdxUsd).symbol();

        initInputParams[0] = ILendingPoolConfigurator.InitReserveInput({
            aTokenImpl: _aTokenAddress,
            variableDebtTokenImpl: address(_variableDebtToken),
            underlyingAssetDecimals: ERC20(_cdxUsd).decimals(),
            interestRateStrategyAddress: _interestStrategy,
            underlyingAsset: _cdxUsd,
            reserveType: false,
            treasury: configAddresses.treasury,
            incentivesController: configAddresses.rewarder,
            underlyingAssetName: tmpSymbol,
            aTokenName: string.concat("Cod3x Lend ", tmpSymbol),
            aTokenSymbol: string.concat("cl", tmpSymbol),
            variableDebtTokenName: string.concat("Cod3x Lend variable debt bearing ", tmpSymbol),
            variableDebtTokenSymbol: string.concat("variableDebt", tmpSymbol),
            params: "0x10"
        });

        vm.prank(owner);
        LendingPoolConfigurator(address(lendingPoolConfigurator)).batchInitReserve(initInputParams);
        // revert("eeee");

        inputConfigParams[0] = ATokensAndRatesHelper.ConfigureReserveInput({
            asset: _cdxUsd,
            reserveType: false,
            baseLTV: 8000,
            liquidationThreshold: 8500,
            liquidationBonus: 10500,
            reserveFactor: 0,
            borrowingEnabled: true
        });

        lendingPoolAddressesProvider.setPoolAdmin(configAddresses.aTokensAndRatesHelper);
        ATokensAndRatesHelper(configAddresses.aTokensAndRatesHelper).configureReserves(
            inputConfigParams
        );
        lendingPoolAddressesProvider.setPoolAdmin(owner);
    }

    // ======= Cod3x Lend =======

    function uintToString(uint256 value) public pure returns (string memory) {
        // Special case for 0
        if (value == 0) {
            return "0";
        }

        uint256 temp = value;
        uint256 digits;

        // Calculate the number of digits
        while (temp != 0) {
            digits++;
            temp /= 10;
        }

        bytes memory buffer = new bytes(digits);

        // Fill the buffer with the digits in reverse order
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }

        return string(buffer);
    }

    function fixture_deployProtocol() public returns (DeployedContracts memory) {
        DeployedContracts memory deployedContracts;

        LendingPool lendingPool;
        address lendingPoolProxyAddress;
        // LendingPool lendingPoolProxy;
        // Treasury treasury;
        LendingPoolConfigurator lendingPoolConfigurator;
        address lendingPoolConfiguratorProxyAddress;
        // LendingPoolConfigurator lendingPoolConfiguratorProxy;
        // bytes memory args = abi.encode();
        // bytes memory bytecode = abi.encodePacked(vm.getCode("contracts/incentives/Rewarder.sol:Rewarder"));
        // address anotherAddress;
        // assembly {
        //     anotherAddress := create(0, add(bytecode, 0x20), mload(bytecode))
        // }
        deployedContracts.rewarder = new Rewarder();

        deployedContracts.lendingPoolAddressesProvider = new LendingPoolAddressesProvider();

        deployedContracts.lendingPoolAddressesProvider.setPoolAdmin(owner);
        deployedContracts.lendingPoolAddressesProvider.setEmergencyAdmin(owner);

        lendingPool = new LendingPool();
        deployedContracts.lendingPoolAddressesProvider.setLendingPoolImpl(address(lendingPool));
        lendingPoolProxyAddress =
            address(deployedContracts.lendingPoolAddressesProvider.getLendingPool());
        deployedContracts.lendingPool = LendingPool(lendingPoolProxyAddress);
        deployedContracts.treasury = new Treasury(deployedContracts.lendingPoolAddressesProvider);

        lendingPoolConfigurator = new LendingPoolConfigurator();
        deployedContracts.lendingPoolAddressesProvider.setLendingPoolConfiguratorImpl(
            address(lendingPoolConfigurator)
        );
        lendingPoolConfiguratorProxyAddress =
            deployedContracts.lendingPoolAddressesProvider.getLendingPoolConfigurator();
        deployedContracts.lendingPoolConfigurator =
            LendingPoolConfigurator(lendingPoolConfiguratorProxyAddress);
        vm.prank(owner);
        deployedContracts.lendingPoolConfigurator.setPoolPause(true);

        // stableAndVariableTokensHelper = new StableAndVariableTokensHelper(lendingPoolProxyAddress, address(lendingPoolAddressesProvider));
        deployedContracts.aTokensAndRatesHelper = new ATokensAndRatesHelper(
            payable(lendingPoolProxyAddress),
            address(deployedContracts.lendingPoolAddressesProvider),
            lendingPoolConfiguratorProxyAddress
        );

        commonContracts.aToken = new AToken();
        commonContracts.aTokenErc6909 = new ATokenERC6909();
        commonContracts.variableDebtToken = new VariableDebtToken();
        // stableDebtToken = new StableDebtToken();
        fixture_deployMocks(
            address(deployedContracts.treasury), address(deployedContracts.lendingPoolConfigurator)
        );
        deployedContracts.lendingPoolAddressesProvider.setPriceOracle(
            address(commonContracts.oracle)
        );
        vm.label(address(commonContracts.oracle), "Oracle");
        deployedContracts.cod3xLendDataProvider =
            new Cod3xLendDataProvider(ETH_USD_SOURCE, USDC_USD_SOURCE);
        deployedContracts.cod3xLendDataProvider.setLendingPoolAddressProvider(
            address(deployedContracts.lendingPoolAddressesProvider)
        );
        commonContracts.wETHGateway = new WETHGateway(weth);
        deployedContracts.stableStrategy = new DefaultReserveInterestRateStrategy(
            deployedContracts.lendingPoolAddressesProvider,
            sStrat[0],
            sStrat[1],
            sStrat[2],
            sStrat[3]
        );
        deployedContracts.volatileStrategy = new DefaultReserveInterestRateStrategy(
            deployedContracts.lendingPoolAddressesProvider,
            volStrat[0],
            volStrat[1],
            volStrat[2],
            volStrat[3]
        );

        commonContracts.defaultPidConfig = PidConfig({
            asset: dai,
            assetReserveType: true,
            minControllerError: -400e24,
            maxITimeAmp: 20 days,
            optimalUtilizationRate: 45e25,
            kp: 1e27,
            ki: 13e19
        });
        deployedContracts.piStrategy = new PiReserveInterestRateStrategy(
            address(deployedContracts.lendingPoolAddressesProvider),
            commonContracts.defaultPidConfig.asset,
            commonContracts.defaultPidConfig.assetReserveType,
            commonContracts.defaultPidConfig.minControllerError,
            commonContracts.defaultPidConfig.maxITimeAmp,
            commonContracts.defaultPidConfig.optimalUtilizationRate,
            commonContracts.defaultPidConfig.kp,
            commonContracts.defaultPidConfig.ki
        );

        return (deployedContracts);
    }

    function fixture_deployMocks(address _treasury, address _lendingPoolConfigurator) public {
        /* Prices to be changed here */
        ERC20[] memory erc20tokens = fixture_getErc20Tokens(tokens);
        int256[] memory prices = new int256[](3);
        uint256[] memory timeouts = new uint256[](3);
        /* All chainlink price feeds have 8 decimals */
        // prices[0] = int256(1 * 10 ** PRICE_FEED_DECIMALS); // USDC
        prices[0] = int256(67_000 * 10 ** PRICE_FEED_DECIMALS); // WBTC
        prices[1] = int256(3700 * 10 ** PRICE_FEED_DECIMALS); // ETH
        prices[2] = int256(1 * 10 ** PRICE_FEED_DECIMALS); // DAI
        // usdcPriceFeed = new MockAggregator(100000000, int256(uint256(mintableUsdc.decimals())));
        // wbtcPriceFeed = new MockAggregator(1600000000000, int256(uint256(mintableWbtc.decimals())));
        // ethPriceFeed = new MockAggregator(120000000000, int256(uint256(mintableWeth.decimals())));
        (, commonContracts.aggregators, timeouts) = fixture_getTokenPriceFeeds(erc20tokens, prices);

        commonContracts.oracle = new Oracle(
            tokens,
            commonContracts.aggregators,
            timeouts,
            FALLBACK_ORACLE,
            BASE_CURRENCY,
            BASE_CURRENCY_UNIT,
            _lendingPoolConfigurator
        );

        commonContracts.wETHGateway = new WETHGateway(weth);
    }

    function fixture_configureProtocol(
        address lendingPool,
        address _aToken,
        ConfigAddresses memory configAddresses,
        LendingPoolConfigurator lendingPoolConfiguratorProxy,
        LendingPoolAddressesProvider lendingPoolAddressesProvider
    ) public {
        fixture_configureReserves(
            configAddresses, lendingPoolConfiguratorProxy, lendingPoolAddressesProvider, _aToken
        );

        // commonContracts.wETHGateway.authorizeLendingPool(lendingPool);

        vm.prank(owner);
        lendingPoolConfiguratorProxy.setPoolPause(false);

        commonContracts.aTokens =
            fixture_getATokens(tokens, Cod3xLendDataProvider(configAddresses.cod3xLendDataProvider));
        commonContracts.aTokensWrapper = fixture_getATokensWrapper(
            tokens, Cod3xLendDataProvider(configAddresses.cod3xLendDataProvider)
        );
        commonContracts.variableDebtTokens = fixture_getVarDebtTokens(
            tokens, Cod3xLendDataProvider(configAddresses.cod3xLendDataProvider)
        );
        for (uint256 idx; idx < tokens.length; idx++) {
            vm.label(
                address(commonContracts.aTokens[idx]), string.concat("AToken ", uintToString(idx))
            );
            vm.label(
                address(commonContracts.variableDebtTokens[idx]),
                string.concat("VariableDebtToken ", uintToString(idx))
            );
        }
    }

    function fixture_configureReserves(
        ConfigAddresses memory configAddresses,
        LendingPoolConfigurator lendingPoolConfigurator,
        LendingPoolAddressesProvider lendingPoolAddressesProvider,
        address aTokenAddress
    ) public {
        ILendingPoolConfigurator.InitReserveInput[] memory initInputParams =
            new ILendingPoolConfigurator.InitReserveInput[](tokens.length);
        ATokensAndRatesHelper.ConfigureReserveInput[] memory inputConfigParams =
            new ATokensAndRatesHelper.ConfigureReserveInput[](tokens.length);

        for (uint8 idx = 0; idx < tokens.length; idx++) {
            string memory tmpSymbol = ERC20(tokens[idx]).symbol();
            address interestStrategy = isStableStrategy[idx] != false
                ? configAddresses.stableStrategy
                : configAddresses.volatileStrategy;
            // console2.log("[common] main interestStartegy: ", interestStrategy);
            initInputParams[idx] = ILendingPoolConfigurator.InitReserveInput({
                aTokenImpl: aTokenAddress,
                variableDebtTokenImpl: address(commonContracts.variableDebtToken),
                underlyingAssetDecimals: ERC20(tokens[idx]).decimals(),
                interestRateStrategyAddress: interestStrategy,
                underlyingAsset: tokens[idx],
                reserveType: reserveTypes[idx],
                treasury: configAddresses.treasury,
                incentivesController: configAddresses.rewarder,
                underlyingAssetName: tmpSymbol,
                aTokenName: string.concat("Cod3x Lend ", tmpSymbol),
                aTokenSymbol: string.concat("cl", tmpSymbol),
                variableDebtTokenName: string.concat("Cod3x Lend variable debt bearing ", tmpSymbol),
                variableDebtTokenSymbol: string.concat("variableDebt", tmpSymbol),
                params: "0x10"
            });
        }

        vm.prank(owner);
        lendingPoolConfigurator.batchInitReserve(initInputParams);

        for (uint8 idx = 0; idx < tokens.length; idx++) {
            inputConfigParams[idx] = ATokensAndRatesHelper.ConfigureReserveInput({
                asset: tokens[idx],
                reserveType: reserveTypes[idx],
                baseLTV: 8000,
                liquidationThreshold: 8500,
                liquidationBonus: 10500,
                reserveFactor: 1500,
                borrowingEnabled: true
            });
        }

        lendingPoolAddressesProvider.setPoolAdmin(configAddresses.aTokensAndRatesHelper);
        ATokensAndRatesHelper(configAddresses.aTokensAndRatesHelper).configureReserves(
            inputConfigParams
        );
        lendingPoolAddressesProvider.setPoolAdmin(owner);
    }

    function fixture_getATokens(
        address[] memory _tokens,
        Cod3xLendDataProvider cod3xLendDataProvider
    ) public view returns (AToken[] memory _aTokens) {
        _aTokens = new AToken[](_tokens.length);
        for (uint32 idx = 0; idx < _tokens.length; idx++) {
            (address _aTokenAddress,) = cod3xLendDataProvider.getLpTokens(_tokens[idx], (_tokens[idx] == address(cdxUsd) ? false : true));
            // console2.log("AToken%s: %s", idx, _aTokenAddress);
            _aTokens[idx] = AToken(_aTokenAddress);
        }
    }

    function fixture_getATokensWrapper(
        address[] memory _tokens,
        Cod3xLendDataProvider cod3xLendDataProvider
    ) public view returns (AToken[] memory _aTokensW) {
        _aTokensW = new AToken[](_tokens.length);
        for (uint32 idx = 0; idx < _tokens.length; idx++) {
            (address _aTokenAddress,) = cod3xLendDataProvider.getLpTokens(_tokens[idx], (_tokens[idx] == address(cdxUsd) ? false : true));
            // console2.log("AToken%s: %s", idx, _aTokenAddress);
            _aTokensW[idx] = AToken(address(AToken(_aTokenAddress).WRAPPER_ADDRESS()));
        }
    }

    function fixture_getVarDebtTokens(
        address[] memory _tokens,
        Cod3xLendDataProvider cod3xLendDataProvider
    ) public returns (VariableDebtToken[] memory _varDebtTokens) {
        _varDebtTokens = new VariableDebtToken[](_tokens.length);
        for (uint32 idx = 0; idx < _tokens.length; idx++) {
            (, address _variableDebtToken) = cod3xLendDataProvider.getLpTokens(_tokens[idx], _tokens[idx] == address(cdxUsd) ? false : true);
            // console2.log("Atoken address", _variableDebtToken);
            string memory debtToken = string.concat("debtToken", uintToString(idx));
            vm.label(_variableDebtToken, debtToken);
            console2.log("Debt token %s: %s", idx, _variableDebtToken);
            _varDebtTokens[idx] = VariableDebtToken(_variableDebtToken);
        }
    }

    function fixture_getErc20Tokens(address[] memory _tokens)
        public
        pure
        returns (ERC20[] memory erc20Tokens)
    {
        erc20Tokens = new ERC20[](_tokens.length);
        for (uint32 idx = 0; idx < _tokens.length; idx++) {
            erc20Tokens[idx] = ERC20(_tokens[idx]);
        }
    }

    function fixture_getTokenPriceFeeds(ERC20[] memory _tokens, int256[] memory _prices)
        public
        returns (
            MockAggregator[] memory _priceFeedMocks,
            address[] memory _aggregators,
            uint256[] memory _timeouts
        )
    {
        require(_tokens.length == _prices.length, "Length of params shall be equal");

        _priceFeedMocks = new MockAggregator[](_tokens.length);
        _aggregators = new address[](_tokens.length);
        _timeouts = new uint256[](_tokens.length);
        for (uint32 idx; idx < _tokens.length; idx++) {
            _priceFeedMocks[idx] =
                new MockAggregator(_prices[idx], int256(uint256(_tokens[idx].decimals())));
            _aggregators[idx] = address(_priceFeedMocks[idx]);
            _timeouts[idx] = 0;
        }
    }

    function fixture_transferTokensToTestContract(
        ERC20[] memory _tokens,
        uint256 _toGiveInUsd,
        address _testContractAddress
    ) public {
        for (uint32 idx = 0; idx < _tokens.length; idx++) {
            console2.log("IDX: ", idx);
            uint256 price = commonContracts.oracle.getAssetPrice(address(_tokens[idx]));
            console2.log("_toGiveInUsd:", _toGiveInUsd);
            uint256 rawGive = (_toGiveInUsd / price) * 10 ** PRICE_FEED_DECIMALS;
            console2.log("rawGive:", rawGive);
            console2.log(
                "Distributed %s of %s",
                rawGive / (10 ** (18 - _tokens[idx].decimals())),
                _tokens[idx].symbol()
            );
            deal(
                address(_tokens[idx]),
                _testContractAddress,
                rawGive / (10 ** (18 - _tokens[idx].decimals()))
            );
            console2.log(
                "Balance: %s %s",
                _tokens[idx].balanceOf(_testContractAddress),
                _tokens[idx].symbol()
            );
        }
    }

    function fixture_convertWithDecimals(uint256 amountRaw, uint256 decimalsA, uint256 decimalsB)
        public
        pure
        returns (uint256)
    {
        return (decimalsA > decimalsB)
            ? amountRaw * (10 ** (decimalsA - decimalsB))
            : amountRaw / (10 ** (decimalsB - decimalsA));
    }

    function fixture_preciseConvertWithDecimals(
        uint256 amountRay,
        uint256 decimalsA,
        uint256 decimalsB
    ) public pure returns (uint256) {
        return (decimalsA > decimalsB)
            ? amountRay / 10 ** (RAY_DECIMALS - PRICE_FEED_DECIMALS + (decimalsA - decimalsB))
            : amountRay / 10 ** (RAY_DECIMALS - PRICE_FEED_DECIMALS - (decimalsB - decimalsA));
    }

    function getUsdValOfToken(uint256 amount, address token) public view returns (uint256) {
        return amount * commonContracts.oracle.getAssetPrice(token);
    }

    function fixture_changePriceOfToken(
        TokenParams memory collateralParams,
        uint256 percentageOfChange,
        bool isPriceIncrease
    ) public returns (uint256) {
        uint256 newUsdcPrice;
        newUsdcPrice = (isPriceIncrease)
            ? (collateralParams.price + collateralParams.price * percentageOfChange / 10_000)
            : (collateralParams.price - collateralParams.price * percentageOfChange / 10_000);
        address collateralSource =
            commonContracts.oracle.getSourceOfAsset(address(collateralParams.token));
        MockAggregator agg = MockAggregator(collateralSource);
        console2.log("1. Latest price: ", uint256(agg.latestAnswer()));

        agg.setLastAnswer(int256(newUsdcPrice));

        console2.log("2. Latest price: ", uint256(agg.latestAnswer()));
        console2.log(
            "2. Oracle price: ",
            commonContracts.oracle.getAssetPrice(address(collateralParams.token))
        );
    }

    function fixture_calcCompoundedInterest(
        uint256 rate,
        uint256 currentTimestamp,
        uint256 lastUpdateTimestamp
    ) public pure returns (uint256) {
        uint256 timeDifference = currentTimestamp - lastUpdateTimestamp;
        if (timeDifference == 0) {
            return WadRayMath.RAY;
        }
        uint256 ratePerSecond = rate / 365 days;

        uint256 expMinusOne = timeDifference - 1;
        uint256 expMinusTwo = (timeDifference > 2) ? timeDifference - 2 : 0;

        uint256 basePowerTwo = ratePerSecond.rayMul(ratePerSecond);
        uint256 basePowerThree = basePowerTwo.rayMul(ratePerSecond);
        uint256 secondTerm = timeDifference * expMinusOne * basePowerTwo / 2;
        uint256 thirdTerm = timeDifference * expMinusOne * expMinusTwo * basePowerThree / 6;

        return WadRayMath.RAY + ratePerSecond * timeDifference + secondTerm + thirdTerm;
    }

    function fixture_calcExpectedVariableDebtTokenBalance(
        uint256 variableBorrowRate,
        uint256 variableBorrowIndex,
        uint256 lastUpdateTimestamp,
        uint256 scaledVariableDebt,
        uint256 txTimestamp
    ) public pure returns (uint256) {
        if (variableBorrowRate == 0) {
            return variableBorrowIndex;
        }
        uint256 cumulatedInterest =
            fixture_calcCompoundedInterest(variableBorrowRate, txTimestamp, lastUpdateTimestamp);
        uint256 normalizedDebt = cumulatedInterest.rayMul(variableBorrowIndex);

        uint256 expectedVariableDebtTokenBalance = scaledVariableDebt.rayMul(normalizedDebt);
        return expectedVariableDebtTokenBalance;
    }

    function fixture_getReserveData(address token, ProtocolDataProvider protocolDataProvider)
    public
    view
    returns (ReserveDataParams memory)
{
    (
        uint256 availableLiquidity,
        uint256 totalVariableDebt,
        uint256 liquidityRate,
        uint256 variableBorrowRate,
        uint256 liquidityIndex,
        uint256 variableBorrowIndex,
        uint40 lastUpdateTimestamp
    ) = protocolDataProvider.getReserveData(token, token == address(cdxUsd) ? false : true);
    return ReserveDataParams(
        availableLiquidity,
        totalVariableDebt,
        liquidityRate,
        variableBorrowRate,
        liquidityIndex,
        variableBorrowIndex,
        lastUpdateTimestamp
    );
}

    // ======= Balancer =======

    function createStablePool(IERC20[] memory assets, uint256 amplificationParameter, address owner)
        public
        returns (bytes32, address)
    {
        // sort tokens
        IERC20[] memory tokens = new IERC20[](assets.length);

        tokens = sort(assets);

        IRateProvider[] memory rateProviders = new IRateProvider[](assets.length);
        for (uint256 i = 0; i < assets.length; i++) {
            rateProviders[i] = IRateProvider(address(0));
        }

        uint256[] memory tokenRateCacheDurations = new uint256[](assets.length);
        for (uint256 i = 0; i < assets.length; i++) {
            tokenRateCacheDurations[i] = uint256(0);
        }

        ComposableStablePool stablePool = IComposableStablePoolFactory(
            address(composableStablePoolFactory)
        ).create(
            "Cod3x-USD-Pool",
            "CUP",
            tokens,
            2500, // test only
            rateProviders,
            tokenRateCacheDurations,
            false,
            1e12,
            owner,
            bytes32("")
        );

        return (stablePool.getPoolId(), address(stablePool));
    }

    function joinPool(
        bytes32 poolId,
        IERC20[] memory setupPoolTokens,
        uint256[] memory amounts,
        address user,
        JoinKind kind
    ) public {
        require(
            kind == JoinKind.INIT || kind == JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT,
            "Operation not supported"
        );

        IERC20[] memory tokens = new IERC20[](setupPoolTokens.length);
        uint256[] memory amountsToAdd = new uint256[](setupPoolTokens.length);

        (tokens, amountsToAdd) = sort(setupPoolTokens, amounts);

        IAsset[] memory assetsIAsset = new IAsset[](setupPoolTokens.length);
        for (uint256 i = 0; i < setupPoolTokens.length; i++) {
            assetsIAsset[i] = IAsset(address(tokens[i]));
        }

        uint256[] memory maxAmounts = new uint256[](setupPoolTokens.length);
        for (uint256 i = 0; i < setupPoolTokens.length; i++) {
            maxAmounts[i] = type(uint256).max;
        }

        IVault.JoinPoolRequest memory request;
        request.assets = assetsIAsset;
        request.maxAmountsIn = maxAmounts;
        request.fromInternalBalance = false;
        if (kind == JoinKind.INIT) {
            request.userData = abi.encode(kind, amountsToAdd);
        } else if (kind == JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT) {
            request.userData = abi.encode(kind, amountsToAdd, 0);
        }

        vm.prank(user);
        IVault(vault).joinPool(poolId, user, user, request);
    }

    function exitPool(
        bytes32 poolId,
        IERC20[] memory setupPoolTokens,
        uint256 amount,
        address user,
        ExitKind kind
    ) public {
        require(kind == ExitKind.EXACT_BPT_IN_FOR_ALL_TOKENS_OUT, "Operation not supported");

        IERC20[] memory tokens = new IERC20[](setupPoolTokens.length);

        tokens = sort(setupPoolTokens);

        IAsset[] memory assetsIAsset = new IAsset[](setupPoolTokens.length);
        for (uint256 i = 0; i < setupPoolTokens.length; i++) {
            assetsIAsset[i] = IAsset(address(tokens[i]));
        }

        uint256[] memory minAmountsOut = new uint256[](setupPoolTokens.length);
        for (uint256 i = 0; i < setupPoolTokens.length; i++) {
            minAmountsOut[i] = 0;
        }

        IVault.ExitPoolRequest memory request;
        request.assets = assetsIAsset;
        request.minAmountsOut = minAmountsOut;
        request.toInternalBalance = false;
        request.userData = abi.encode(kind, amount);

        vm.prank(user);
        IVault(vault).exitPool(poolId, user, payable(user), request);
    }

    function swap(
        bytes32 poolId,
        address user,
        address assetIn,
        address assetOut,
        uint256 amount,
        uint256 limit,
        uint256 deadline,
        SwapKind kind
    ) public {
        require(kind == SwapKind.GIVEN_IN, "Operation not supported");

        IVault.SingleSwap memory singleSwap;
        singleSwap.poolId = poolId;
        singleSwap.kind = kind;
        singleSwap.assetIn = IAsset(assetIn);
        singleSwap.assetOut = IAsset(assetOut);
        singleSwap.amount = amount;
        singleSwap.userData = bytes("");

        IVault.FundManagement memory fundManagement;
        fundManagement.sender = user;
        fundManagement.fromInternalBalance = false;
        fundManagement.recipient = payable(user);
        fundManagement.toInternalBalance = false;

        vm.prank(user);
        IVault(vault).swap(singleSwap, fundManagement, limit, deadline);
    }
}
