// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "lib/Cod3x-Lend/contracts/dependencies/openzeppelin/contracts/ERC20.sol";
import "lib/Cod3x-Lend/contracts/protocol/rewarder/lendingpool/Rewarder.sol";
import "lib/Cod3x-Lend/contracts/protocol/core/Oracle.sol";
import "lib/Cod3x-Lend/contracts/misc/ProtocolDataProvider.sol";
import "lib/Cod3x-Lend/contracts/misc/Treasury.sol";
import "lib/Cod3x-Lend/contracts/misc/UiPoolDataProviderV2.sol";
import "lib/Cod3x-Lend/contracts/misc/WETHGateway.sol";
import "lib/Cod3x-Lend/contracts/protocol/core/lendingPool/logic/ReserveLogic.sol";
import "lib/Cod3x-Lend/contracts/protocol/core/lendingPool/logic/GenericLogic.sol";
import "lib/Cod3x-Lend/contracts/protocol/core/lendingPool/logic/ValidationLogic.sol";
import "lib/Cod3x-Lend/contracts/protocol/configuration/LendingPoolAddressesProvider.sol";
import "lib/Cod3x-Lend/contracts/protocol/configuration/LendingPoolAddressesProviderRegistry.sol";
import
    "lib/Cod3x-Lend/contracts/protocol/core/interestRateStrategies/DefaultReserveInterestRateStrategy.sol";
import "lib/Cod3x-Lend/contracts/protocol/core/lendingpool/LendingPool.sol";
import "lib/Cod3x-Lend/contracts/protocol/core/lendingpool/LendingPoolCollateralManager.sol";
import "lib/Cod3x-Lend/contracts/protocol/core/lendingpool/LendingPoolConfigurator.sol";
import "lib/Cod3x-Lend/contracts/protocol/core/minipool/MiniPool.sol";
import "lib/Cod3x-Lend/contracts/protocol/configuration/MiniPoolAddressProvider.sol";
import "lib/Cod3x-Lend/contracts/protocol/core/minipool/MiniPoolConfigurator.sol";
import "lib/Cod3x-Lend/contracts/protocol/core/minipool/FlowLimiter.sol";

import "lib/Cod3x-Lend/contracts/deployments/ATokensAndRatesHelper.sol";
import "lib/Cod3x-Lend/contracts/protocol/tokenization/ERC20/AToken.sol";
import "lib/Cod3x-Lend/contracts/protocol/tokenization/ERC6909/ATokenERC6909.sol";
import "lib/Cod3x-Lend/contracts/protocol/tokenization/ERC20/VariableDebtToken.sol";
import "lib/Cod3x-Lend/contracts/mocks/tokens/MintableERC20.sol";
import "lib/Cod3x-Lend/contracts/mocks/tokens/WETH9Mocked.sol";
import "lib/Cod3x-Lend/contracts/mocks/oracle/MockAggregator.sol";
import "lib/Cod3x-Lend/contracts/mocks/tokens/MockVault.sol";
import "lib/Cod3x-Lend/contracts/mocks/tokens/ExternalContract.sol";
import "lib/Cod3x-Lend/contracts/mocks/dependencies/IStrategy.sol";
import "lib/Cod3x-Lend/contracts/mocks/dependencies/IExternalContract.sol";
import {WadRayMath} from "lib/Cod3x-Lend/contracts/protocol/libraries/math/WadRayMath.sol";

import
    "lib/Cod3x-Lend/contracts/protocol/core/interestRateStrategies/MiniPoolDefaultReserveInterestRate.sol";
import "lib/Cod3x-Lend/contracts/mocks/oracle/PriceOracle.sol";
import "lib/Cod3x-Lend/contracts/protocol/core/minipool/MiniPoolCollateralManager.sol";

struct ReserveDataParams {
    uint256 availableLiquidity;
    uint256 totalVariableDebt;
    uint256 liquidityRate;
    uint256 variableBorrowRate;
    uint256 liquidityIndex;
    uint256 variableBorrowIndex;
    uint40 lastUpdateTimestamp;
}

contract Common is TestHelperOz5, Events {
    using WadRayMath for uint256;

    // Structures
    struct ConfigAddresses {
        address protocolDataProvider;
        address stableStrategy;
        address volatileStrategy;
        address treasury;
        address rewarder;
        address aTokensAndRatesHelper;
    }

    struct DeployedContracts {
        LendingPoolAddressesProviderRegistry lendingPoolAddressesProviderRegistry;
        Rewarder rewarder;
        LendingPoolAddressesProvider lendingPoolAddressesProvider;
        LendingPool lendingPool;
        Treasury treasury;
        LendingPoolConfigurator lendingPoolConfigurator;
        DefaultReserveInterestRateStrategy stableStrategy;
        DefaultReserveInterestRateStrategy volatileStrategy;
        ProtocolDataProvider protocolDataProvider;
        ATokensAndRatesHelper aTokensAndRatesHelper;
    }

    struct DeployedMiniPoolContracts {
        MiniPool miniPoolImpl;
        MiniPoolAddressesProvider miniPoolAddressesProvider;
        MiniPoolConfigurator miniPoolConfigurator;
        ATokenERC6909 aToken6909Impl;
        flowLimiter flowLimiter;
    }

    struct TokenParams {
        ERC20 token;
        AToken aToken;
        uint256 price;
    }

    struct Users {
        address user1;
        address user2;
        address user3;
        address user4;
        address user5;
        address user6;
        address user7;
        address user8;
        address user9;
    }

    // Fork Identifier
    string RPC = vm.envString("OPTIMISM_RPC_URL");
    uint256 constant FORK_BLOCK = 116753757;
    uint256 public opFork;

    // Constants
    address constant ZERO_ADDRESS = address(0);
    address constant BASE_CURRENCY = address(0);
    uint256 constant BASE_CURRENCY_UNIT = 100000000;
    address constant FALLBACK_ORACLE = address(0);
    uint256 constant TVL_CAP = 1e20;
    uint256 constant PERCENTAGE_FACTOR = 10_000;
    uint8 constant PRICE_FEED_DECIMALS = 8;
    uint8 constant RAY_DECIMALS = 27;

    // Tokens addresses
    address constant USDC = 0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85;
    address constant WBTC = 0x68f180fcCe6836688e9084f035309E29Bf0A2095;
    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant DAI = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1;
    address constant USDC_WHALE = 0x383BB83D698733b021dD4d943c12BB12217f9AB8;
    address constant WBTC_WHALE = 0x99b7AE9ff695C0430D63460C69b141F7703349e7;
    address constant WETH_WHALE = 0x240F670a93e7DAC470d22722Aba5f7ff8915c5f2;
    address constant DAI_WHALE = 0x1eED63EfBA5f81D95bfe37d82C8E736b974F477b;

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

    address[] tokens = [ /* USDC,*/ WBTC, WETH, DAI];
    address[] tokensWhales = [ /* USDC_WHALE,*/ WBTC_WHALE, WETH_WHALE, DAI_WHALE];

    address admin = 0xe027880CEB8114F2e367211dF977899d00e66138;
    uint256[] rates = [0.039e27, 0.03e27, 0.03e27]; //usdc, wbtc, eth
    uint256[] volStrat = [
        VOLATILE_OPTIMAL_UTILIZATION_RATE,
        VOLATILE_BASE_VARIABLE_BORROW_RATE,
        VOLATILE_VARIABLE_RATE_SLOPE_1,
        VOLATILE_VARIABLE_RATE_SLOPE_2
    ]; // optimalUtilizationRate, baseVariableBorrowRate, variableRateSlope1, variableRateSlope2
    uint256[] sStrat = [
        STABLE_OPTIMAL_UTILIZATION_RATE,
        STABLE_BASE_VARIABLE_BORROW_RATE,
        STABLE_VARIABLE_RATE_SLOPE_1,
        STABLE_VARIABLE_RATE_SLOPE_2
    ]; // optimalUtilizationRate, baseVariableBorrowRate, variableRateSlope1, variableRateSlope2
    bool[] isStableStrategy = [true, false, false, true];
    bool[] reserveTypes = [true, true, true, true];
    // Protocol deployment variables
    uint256 providerId = 1;
    string marketId = "Cod3x Lend Genesis Market";
    uint256 cntr;

    ERC20 public weth = ERC20(WETH);
    ERC20 public dai = ERC20(DAI);

    // MockAggregator public usdcPriceFeed;
    // MockAggregator public wbtcPriceFeed;
    // MockAggregator public ethPriceFeed;
    address[] public aggregators;

    address public reserveLogic;
    address public genericLogic;
    address public validationLogic;

    // StableAndVariableTokensHelper public stableAndVariableTokensHelper;
    Oracle public oracle;

    UiPoolDataProviderV2 public uiPoolDataProviderV2;
    WETHGateway public wETHGateway;
    AToken public aToken;
    VariableDebtToken public variableDebtToken;
    ATokenERC6909 public aTokenErc6909;

    LendingPoolCollateralManager public lendingPoolCollateralManager;
    AToken[] public aTokens;
    VariableDebtToken[] public variableDebtTokens;
    ATokenERC6909[] public aTokensErc6909;

    MockERC4626[] public mockedVaults;

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
        deployedContracts.lendingPoolAddressesProviderRegistry =
            new LendingPoolAddressesProviderRegistry();
        deployedContracts.lendingPoolAddressesProvider = new LendingPoolAddressesProvider(marketId);
        deployedContracts.lendingPoolAddressesProviderRegistry.registerAddressesProvider(
            address(deployedContracts.lendingPoolAddressesProvider), providerId
        );
        deployedContracts.lendingPoolAddressesProvider.setPoolAdmin(admin);
        deployedContracts.lendingPoolAddressesProvider.setEmergencyAdmin(admin);

        // reserveLogic = address(new ReserveLogic());
        // genericLogic = address(new GenericLogic());
        // validationLogic = address(new ValidationLogic());
        lendingPool = new LendingPool();
        lendingPool.initialize(
            ILendingPoolAddressesProvider(deployedContracts.lendingPoolAddressesProvider)
        );
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
        vm.prank(admin);
        deployedContracts.lendingPoolConfigurator.setPoolPause(true);

        // stableAndVariableTokensHelper = new StableAndVariableTokensHelper(lendingPoolProxyAddress, address(lendingPoolAddressesProvider));
        deployedContracts.aTokensAndRatesHelper = new ATokensAndRatesHelper(
            payable(lendingPoolProxyAddress),
            address(deployedContracts.lendingPoolAddressesProvider),
            lendingPoolConfiguratorProxyAddress
        );

        aToken = new AToken();
        aTokenErc6909 = new ATokenERC6909();
        variableDebtToken = new VariableDebtToken();
        // stableDebtToken = new StableDebtToken();
        fixture_deployMocks(address(deployedContracts.treasury));
        deployedContracts.lendingPoolAddressesProvider.setPriceOracle(address(oracle));
        vm.label(address(oracle), "Oracle");
        deployedContracts.protocolDataProvider =
            new ProtocolDataProvider(deployedContracts.lendingPoolAddressesProvider);
        //@todo uiPoolDataProviderV2 = new UiPoolDataProviderV2(IChainlinkAggregator(ethPriceFeed), IChainlinkAggregator(ethPriceFeed));
        wETHGateway = new WETHGateway(WETH);
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

        return (deployedContracts);
    }

    function fixture_deployMocks(address _treasury) public {
        /* Prices to be changed here */
        ERC20[] memory erc20tokens = fixture_getErc20Tokens(tokens);
        int256[] memory prices = new int256[](tokens.length);
        /* All chainlink price feeds have 8 decimals */
        // prices[0] = int256(1 * 10 ** PRICE_FEED_DECIMALS); // USDC
        prices[0] = int256(67_000 * 10 ** PRICE_FEED_DECIMALS); // WBTC
        prices[1] = int256(3700 * 10 ** PRICE_FEED_DECIMALS); // ETH
        prices[2] = int256(1 * 10 ** PRICE_FEED_DECIMALS); // DAI
        mockedVaults = fixture_deployErc4626Mocks(tokens, _treasury);
        // usdcPriceFeed = new MockAggregator(100000000, int256(uint256(mintableUsdc.decimals())));
        // wbtcPriceFeed = new MockAggregator(1600000000000, int256(uint256(mintableWbtc.decimals())));
        // ethPriceFeed = new MockAggregator(120000000000, int256(uint256(mintableWeth.decimals())));
        (, aggregators) = fixture_getTokenPriceFeeds(erc20tokens, prices);

        oracle = new Oracle(tokens, aggregators, FALLBACK_ORACLE, BASE_CURRENCY, BASE_CURRENCY_UNIT);

        wETHGateway = new WETHGateway(WETH);
        lendingPoolCollateralManager = new LendingPoolCollateralManager();
    }

    function fixture_configureProtocol(
        address ledingPool,
        address _aToken,
        ConfigAddresses memory configAddresses,
        LendingPoolConfigurator lendingPoolConfiguratorProxy,
        LendingPoolAddressesProvider lendingPoolAddressesProvider
    ) public {
        fixture_configureReserves(
            configAddresses, lendingPoolConfiguratorProxy, lendingPoolAddressesProvider, _aToken
        );
        lendingPoolAddressesProvider.setLendingPoolCollateralManager(
            address(lendingPoolCollateralManager)
        );
        wETHGateway.authorizeLendingPool(ledingPool);

        vm.prank(admin);
        lendingPoolConfiguratorProxy.setPoolPause(false);

        aTokens =
            fixture_getATokens(tokens, ProtocolDataProvider(configAddresses.protocolDataProvider));
        variableDebtTokens = fixture_getVarDebtTokens(
            tokens, ProtocolDataProvider(configAddresses.protocolDataProvider)
        );
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
            initInputParams[idx] = ILendingPoolConfigurator.InitReserveInput({
                aTokenImpl: aTokenAddress,
                variableDebtTokenImpl: address(variableDebtToken),
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

        vm.prank(admin);
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
        lendingPoolAddressesProvider.setPoolAdmin(admin);
    }

    function fixture_getATokens(address[] memory _tokens, ProtocolDataProvider protocolDataProvider)
        public
        view
        returns (AToken[] memory _aTokens)
    {
        _aTokens = new AToken[](_tokens.length);
        for (uint32 idx = 0; idx < _tokens.length; idx++) {
            // console.log("Index: ", idx);
            (address _aTokenAddress,) =
                protocolDataProvider.getReserveTokensAddresses(_tokens[idx], true);
            // console.log("Atoken address", _aTokenAddress);
            console.log("AToken%s: %s", idx, _aTokenAddress);
            _aTokens[idx] = AToken(_aTokenAddress);
        }
    }

    function fixture_getVarDebtTokens(
        address[] memory _tokens,
        ProtocolDataProvider protocolDataProvider
    ) public returns (VariableDebtToken[] memory _varDebtTokens) {
        _varDebtTokens = new VariableDebtToken[](_tokens.length);
        for (uint32 idx = 0; idx < _tokens.length; idx++) {
            // console.log("Index: ", idx);
            (, address _variableDebtToken) =
                protocolDataProvider.getReserveTokensAddresses(_tokens[idx], true);
            // console.log("Atoken address", _variableDebtToken);
            string memory debtToken = string.concat("debtToken", uintToString(idx));
            vm.label(_variableDebtToken, debtToken);
            console.log("Debt token%s: %s", idx, _variableDebtToken);
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
        returns (MockAggregator[] memory _priceFeedMocks, address[] memory _aggregators)
    {
        require(_tokens.length == _prices.length, "Length of params shall be equal");

        _priceFeedMocks = new MockAggregator[](_tokens.length);
        _aggregators = new address[](_tokens.length);
        for (uint32 idx; idx < _tokens.length; idx++) {
            _priceFeedMocks[idx] =
                new MockAggregator(_prices[idx], int256(uint256(_tokens[idx].decimals())));
            _aggregators[idx] = address(_priceFeedMocks[idx]);
        }
    }

    function fixture_deployErc4626Mocks(address[] memory _tokens, address _treasury)
        public
        returns (MockERC4626[] memory)
    {
        MockERC4626[] memory _mockedVaults = new MockERC4626[](_tokens.length);
        for (uint32 idx = 0; idx < _tokens.length; idx++) {
            _mockedVaults[idx] =
                new MockERC4626(_tokens[idx], "Mock ERC4626", "mock", TVL_CAP, _treasury);
        }
        return _mockedVaults;
    }

    function fixture_transferTokensToTestContract(
        ERC20[] memory _tokens,
        uint256 _toGiveInUsd,
        address _testContractAddress
    ) public {
        require(_tokens.length == tokensWhales.length);
        for (uint32 idx = 0; idx < _tokens.length; idx++) {
            uint256 price = oracle.getAssetPrice(address(_tokens[idx]));
            console.log("price:", price);
            console.log("_toGiveInUsd:", _toGiveInUsd);
            uint256 rawGive = (_toGiveInUsd / price) * 10 ** PRICE_FEED_DECIMALS;
            console.log("rawGive:", rawGive);
            console.log(
                "Distributed %s of %s",
                rawGive / (10 ** (18 - _tokens[idx].decimals())),
                _tokens[idx].symbol()
            );
            deal(
                address(_tokens[idx]),
                _testContractAddress,
                rawGive / (10 ** (18 - _tokens[idx].decimals()))
            );
            console.log(
                "Balance: %s %s",
                _tokens[idx].balanceOf(_testContractAddress),
                _tokens[idx].symbol()
            );
        }
    }

    function fixture_deployMiniPoolSetup(
        address _lendingPoolAddressesProvider,
        address _lendingPool
    ) public returns (DeployedMiniPoolContracts memory) {
        DeployedMiniPoolContracts memory deployedMiniPoolContracts;
        deployedMiniPoolContracts.miniPoolImpl = new MiniPool();
        deployedMiniPoolContracts.miniPoolAddressesProvider = new MiniPoolAddressesProvider(
            ILendingPoolAddressesProvider(_lendingPoolAddressesProvider)
        );
        deployedMiniPoolContracts.aToken6909Impl = new ATokenERC6909();
        deployedMiniPoolContracts.flowLimiter = new flowLimiter(
            ILendingPoolAddressesProvider(_lendingPoolAddressesProvider),
            IMiniPoolAddressesProvider(address(deployedMiniPoolContracts.miniPoolAddressesProvider)),
            ILendingPool(_lendingPool)
        );
        address miniPoolConfigIMPL = address(new MiniPoolConfigurator());
        deployedMiniPoolContracts.miniPoolAddressesProvider.setMiniPoolConfigurator(
            miniPoolConfigIMPL
        );
        deployedMiniPoolContracts.miniPoolConfigurator = MiniPoolConfigurator(
            deployedMiniPoolContracts.miniPoolAddressesProvider.getMiniPoolConfigurator()
        );

        deployedMiniPoolContracts.miniPoolAddressesProvider.setMiniPoolImpl(
            address(deployedMiniPoolContracts.miniPoolImpl)
        );
        deployedMiniPoolContracts.miniPoolAddressesProvider.setAToken6909Impl(
            address(deployedMiniPoolContracts.aToken6909Impl)
        );

        ILendingPoolAddressesProvider(_lendingPoolAddressesProvider).setMiniPoolAddressesProvider(
            address(deployedMiniPoolContracts.miniPoolAddressesProvider)
        );
        ILendingPoolAddressesProvider(_lendingPoolAddressesProvider).setFlowLimiter(
            address(deployedMiniPoolContracts.flowLimiter)
        );
        return deployedMiniPoolContracts;
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

    function fixture_configureMiniPoolReserves(
        address[] memory tokensToConfigure,
        ConfigAddresses memory configAddresses,
        DeployedMiniPoolContracts memory miniPoolContracts
    ) public returns (address) {
        IMiniPoolConfigurator.InitReserveInput[] memory initInputParams =
            new IMiniPoolConfigurator.InitReserveInput[](tokensToConfigure.length);
        // address aTokensErc6909Addr;
        uint256[] memory ssStrat = new uint256[](4);
        ssStrat[0] = uint256(0.75e27);
        ssStrat[1] = uint256(0e27);
        ssStrat[2] = uint256(0.01e27);
        ssStrat[3] = uint256(0.1e27);

        MiniPoolDefaultReserveInterestRateStrategy IRS = new MiniPoolDefaultReserveInterestRateStrategy(
            IMiniPoolAddressesProvider(address(miniPoolContracts.miniPoolAddressesProvider)),
            ssStrat[0],
            ssStrat[1],
            ssStrat[2],
            ssStrat[3]
        );

        miniPoolContracts.miniPoolAddressesProvider.deployMiniPool();
        console.log("Getting Mini pool: ");
        address mp = miniPoolContracts.miniPoolAddressesProvider.getMiniPool(cntr);
        cntr++;
        // aTokensErc6909Addr = miniPoolContracts.miniPoolAddressesProvider.getMiniPoolToAERC6909(mp);
        console.log("Length:", tokensToConfigure.length);
        for (uint8 idx = 0; idx < tokensToConfigure.length; idx++) {
            string memory tmpSymbol = ERC20(tokensToConfigure[idx]).symbol();
            string memory tmpName = ERC20(tokensToConfigure[idx]).name();

            address interestStrategy = isStableStrategy[idx % tokens.length] != false
                ? configAddresses.stableStrategy
                : configAddresses.volatileStrategy;

            initInputParams[idx] = IMiniPoolConfigurator.InitReserveInput({
                underlyingAssetDecimals: ERC20(tokensToConfigure[idx]).decimals(),
                interestRateStrategyAddress: interestStrategy,
                underlyingAsset: tokensToConfigure[idx],
                underlyingAssetName: tmpName,
                underlyingAssetSymbol: tmpSymbol
            });
        }
        vm.startPrank(address(miniPoolContracts.miniPoolAddressesProvider.getPoolAdmin()));
        miniPoolContracts.miniPoolConfigurator.batchInitReserve(initInputParams, IMiniPool(mp));
        assertEq(
            miniPoolContracts.miniPoolAddressesProvider.getMiniPoolConfigurator(),
            address(miniPoolContracts.miniPoolConfigurator)
        );

        for (uint8 idx = 0; idx < tokensToConfigure.length; idx++) {
            miniPoolContracts.miniPoolConfigurator.configureReserveAsCollateral(
                tokensToConfigure[idx], true, 9500, 9700, 10100, IMiniPool(mp)
            );

            miniPoolContracts.miniPoolConfigurator.activateReserve(
                tokensToConfigure[idx], true, IMiniPool(mp)
            );

            miniPoolContracts.miniPoolConfigurator.enableBorrowingOnReserve(
                tokensToConfigure[idx], true, IMiniPool(mp)
            );

            miniPoolContracts.miniPoolConfigurator.setReserveInterestRateStrategyAddress(
                address(tokensToConfigure[idx]), true, address(IRS), IMiniPool(mp)
            );
        }
        vm.stopPrank();
        return (mp);
    }

    function getUsdValOfToken(uint256 amount, address token) public view returns (uint256) {
        return amount * oracle.getAssetPrice(token);
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
        ) = protocolDataProvider.getReserveData(token, true);
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

    function fixture_changePriceOfToken(
        TokenParams memory collateralParams,
        uint256 percentageOfChange,
        bool isPriceIncrease
    ) public returns (uint256) {
        uint256 newUsdcPrice;
        newUsdcPrice = (isPriceIncrease)
            ? (collateralParams.price + collateralParams.price * percentageOfChange / 10_000)
            : (collateralParams.price - collateralParams.price * percentageOfChange / 10_000);
        address collateralSource = oracle.getSourceOfAsset(address(collateralParams.token));
        MockAggregator agg = MockAggregator(collateralSource);
        console.log("1. Latest price: ", uint256(agg.latestAnswer()));

        agg.setLastAnswer(int256(newUsdcPrice));

        console.log("2. Latest price: ", uint256(agg.latestAnswer()));
        console.log("2. Oracle price: ", oracle.getAssetPrice(address(collateralParams.token)));
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
}
