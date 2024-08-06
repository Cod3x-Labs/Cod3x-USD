// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

// Cod3x Lend
import {ERC20} from "lib/Cod3x-Lend/contracts/dependencies/openzeppelin/contracts/ERC20.sol";
import {Rewarder} from "lib/Cod3x-Lend/contracts/rewarder/Rewarder.sol";
import {Oracle} from "lib/Cod3x-Lend/contracts/misc/Oracle.sol";
import {ProtocolDataProvider} from "lib/Cod3x-Lend/contracts/misc/ProtocolDataProvider.sol";
import {Treasury} from "lib/Cod3x-Lend/contracts/misc/Treasury.sol";
import {UiPoolDataProviderV2} from "lib/Cod3x-Lend/contracts/misc/UiPoolDataProviderV2.sol";
import {WETHGateway} from "lib/Cod3x-Lend/contracts/misc/WETHGateway.sol";
import {ReserveLogic} from "lib/Cod3x-Lend/contracts/protocol/libraries/logic/ReserveLogic.sol";
import {GenericLogic} from "lib/Cod3x-Lend/contracts/protocol/libraries/logic/GenericLogic.sol";
import {ValidationLogic} from "lib/Cod3x-Lend/contracts/protocol/libraries/logic/ValidationLogic.sol";
import {LendingPoolAddressesProvider} from "lib/Cod3x-Lend/contracts/protocol/configuration/LendingPoolAddressesProvider.sol";
import {LendingPoolAddressesProviderRegistry} from "lib/Cod3x-Lend/contracts/protocol/configuration/LendingPoolAddressesProviderRegistry.sol";
import {DefaultReserveInterestRateStrategy} from "lib/Cod3x-Lend/contracts/protocol/lendingpool/interestRateStrategies/DefaultReserveInterestRateStrategy.sol";
import {LendingPool} from "lib/Cod3x-Lend/contracts/protocol/lendingpool/LendingPool.sol";
import {LendingPoolCollateralManager} from "lib/Cod3x-Lend/contracts/protocol/lendingpool/LendingPoolCollateralManager.sol";
import {LendingPoolConfigurator} from "lib/Cod3x-Lend/contracts/protocol/lendingpool/LendingPoolConfigurator.sol";
import {MiniPool} from "lib/Cod3x-Lend/contracts/protocol/lendingpool/minipool/MiniPool.sol";
import {MiniPoolAddressesProvider} from "lib/Cod3x-Lend/contracts/protocol/configuration/MiniPoolAddressProvider.sol";
import {MiniPoolConfigurator} from "lib/Cod3x-Lend/contracts/protocol/lendingpool/minipool/MiniPoolConfigurator.sol";
import {flowLimiter} from "lib/Cod3x-Lend/contracts/protocol/lendingpool/minipool/FlowLimiter.sol";
import {ATokensAndRatesHelper} from "lib/Cod3x-Lend/contracts/deployments/ATokensAndRatesHelper.sol";
import {AToken} from "lib/Cod3x-Lend/contracts/protocol/tokenization/AToken.sol";
import {ATokenERC6909} from "lib/Cod3x-Lend/contracts/protocol/tokenization/ERC6909/ATokenERC6909.sol";
import {VariableDebtToken} from "lib/Cod3x-Lend/contracts/protocol/tokenization/VariableDebtToken.sol";
import {MintableERC20} from "lib/Cod3x-Lend/contracts/mocks/tokens/MintableERC20.sol";
import {WETH9Mocked} from "lib/Cod3x-Lend/contracts/mocks/tokens/WETH9Mocked.sol";
import {MockAggregator} from "lib/Cod3x-Lend/contracts/mocks/oracle/CLAggregators/MockAggregator.sol";
import {MockERC4626} from "lib/Cod3x-Lend/contracts/mocks/tokens/MockVault.sol";
import {ExternalContract} from "lib/Cod3x-Lend/contracts/mocks/tokens/ExternalContract.sol";
import {IStrategy} from "lib/Cod3x-Lend/contracts/mocks/dependencies/IStrategy.sol";
import {IExternalContract} from "lib/Cod3x-Lend/contracts/mocks/dependencies/IExternalContract.sol";
import {WadRayMath} from "lib/Cod3x-Lend/contracts/protocol/libraries/math/WadRayMath.sol";
import {MiniPoolDefaultReserveInterestRateStrategy} from "lib/Cod3x-Lend/contracts/protocol/lendingpool/minipool/MiniPoolDefaultReserveInterestRate.sol";
import {PriceOracle} from "lib/Cod3x-Lend/contracts/mocks/oracle/PriceOracle.sol";
import {MiniPoolCollateralManager} from "lib/Cod3x-Lend/contracts/protocol/lendingpool/minipool/MiniPoolCollateralManager.sol";


// Mock imports
import {OFTMock} from "../helpers/mocks/OFTMock.sol";
import {ERC20Mock} from "../helpers/mocks/ERC20Mock.sol";
import {OFTComposerMock} from "../helpers/mocks/OFTComposerMock.sol";
import {IOFTExtended} from "contracts/tokens/interfaces/IOFTExtended.sol";

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
import "contracts/tokens/interfaces/ICdxUSD.sol";
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
} from "contracts/staking_module/vault_strategy/interfaces/IComposableStablePoolFactory.sol";
import {IAsset} from "node_modules/@balancer-labs/v2-interfaces/contracts/vault/IAsset.sol";
import {IVault, JoinKind, ExitKind, SwapKind} from "contracts/staking_module/vault_strategy/interfaces/IVault.sol";
import "forge-std/console.sol";

contract TestCdxUSDAndLend is TestHelperOz5, Sort, Events, Constants {
    uint32 aEid = 1;
    uint32 bEid = 2;
    uint256 public forkIdEth;

    address[] public tokens; // [WBTC, WETH, DAI];
    uint256[] public rates = [0.039e27, 0.03e27, 0.03e27]; //usdc, wbtc, eth
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
    bool[] public isStableStrategy = [true, false, false, true];
    bool[] public reserveTypes = [true, true, true, true];

    // Protocol deployment variables
    uint256 providerId = 1;
    string marketId = "Cod3x Lend Genesis Market";
    uint256 cntr;

    address public userA = address(0x1);
    address public userB = address(0x2);
    address public userC = address(0x3);
    address public owner = address(this);
    address public guardian = address(0x4);
    address public treasury = address(0x5);

    CdxUSD public cdxUSD;
    IERC20 public counterAsset;

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

    uint128 public constant DEFAULT_CAPACITY = 100_000_000e18;
    uint128 public constant INITIAL_CDXUSD_AMT = 10_000_000e18;
    uint128 public constant INITIAL_COUNTER_ASSET_AMT = 10_000_000e18;

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

    function setUp() public virtual override {
        super.setUp();

        string memory MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");
        forkIdEth = vm.createFork(MAINNET_RPC_URL, 20219106);

        uint128 INITIAL_ETH_MINT = 1000 ether;

        vm.deal(userA, INITIAL_ETH_MINT);
        vm.deal(userB, INITIAL_ETH_MINT);
        vm.deal(userC, INITIAL_ETH_MINT);

        setUpEndpoints(2, LibraryType.UltraLightNode);
        cdxUSD = CdxUSD(
            _deployOApp(
                type(CdxUSD).creationCode,
                abi.encode("aOFT", "aOFT", address(endpoints[aEid]), owner, treasury, guardian)
            )
        );
        cdxUSD.addFacilitator(userA, "user a", DEFAULT_CAPACITY);

        counterAsset = IERC20(address(new ERC20Mock{salt: "1"}(18)));

        /// initial mint
        ERC20Mock(address(counterAsset)).mint(userA, INITIAL_COUNTER_ASSET_AMT);
        ERC20Mock(address(counterAsset)).mint(userB, INITIAL_COUNTER_ASSET_AMT);
        ERC20Mock(address(counterAsset)).mint(userC, INITIAL_COUNTER_ASSET_AMT);

        vm.startPrank(userA); 
        cdxUSD.mint(userA, INITIAL_CDXUSD_AMT);
        cdxUSD.mint(userB, INITIAL_CDXUSD_AMT);
        cdxUSD.mint(address(this), INITIAL_CDXUSD_AMT);
        vm.stopPrank();

        ERC20Mock(address(counterAsset)).mint(userB, INITIAL_COUNTER_ASSET_AMT);

        // MAX approve "vault" by all users
        for (uint160 i = 1; i <= 3; i++) {
            vm.startPrank(address(i)); // address(0x1) == address(1)
            cdxUSD.approve(vault, type(uint256).max);
            counterAsset.approve(vault, type(uint256).max);
            vm.stopPrank();
        }
    }
    function createStablePool(        
        IERC20[] memory assets,
        uint256 amplificationParameter,
        address owner
    ) public returns (bytes32, address) {
        // sort tokens
        IERC20[] memory tokens = new IERC20[](assets.length);

        tokens = sort(assets);

        IRateProvider[] memory rateProviders = new IRateProvider[](assets.length);
        for (uint i = 0; i < assets.length; i++) {
            rateProviders[i] = IRateProvider(address(0));
        }   

        uint256[] memory tokenRateCacheDurations = new uint256[](assets.length);
        for (uint i = 0; i < assets.length; i++) {
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

    function joinPool(bytes32 poolId, IERC20[] memory setupPoolTokens, uint256[] memory amounts, address user, JoinKind kind) public {
        require(kind == JoinKind.INIT || kind == JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT, "Operation not supported");

        IERC20[] memory tokens = new IERC20[](setupPoolTokens.length);
        uint256[] memory amountsToAdd = new uint256[](setupPoolTokens.length);

        (tokens, amountsToAdd) = sort(setupPoolTokens, amounts);

        IAsset[] memory assetsIAsset = new IAsset[](setupPoolTokens.length);
        for (uint i = 0; i < setupPoolTokens.length; i++) {
            assetsIAsset[i] = IAsset(address(tokens[i]));
        }
        
        uint256[] memory maxAmounts = new uint256[](setupPoolTokens.length);
        for (uint i = 0; i < setupPoolTokens.length; i++) {
            maxAmounts[i] = type(uint256).max;
        }

        IVault.JoinPoolRequest memory request;
        request.assets = assetsIAsset;
        request.maxAmountsIn = maxAmounts;
        request.fromInternalBalance = false;
        if (kind == JoinKind.INIT)
            request.userData = abi.encode(kind, amountsToAdd);
        else if (kind == JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT)
            request.userData = abi.encode(kind, amountsToAdd, 0);
        
        vm.prank(user);
        IVault(vault).joinPool(poolId, user, user, request);
    }

    function exitPool(bytes32 poolId, IERC20[] memory setupPoolTokens, uint256 amount, address user, ExitKind kind) public {
        require(kind == ExitKind.EXACT_BPT_IN_FOR_ALL_TOKENS_OUT, "Operation not supported");

        IERC20[] memory tokens = new IERC20[](setupPoolTokens.length);

        tokens = sort(setupPoolTokens);

        IAsset[] memory assetsIAsset = new IAsset[](setupPoolTokens.length);
        for (uint i = 0; i < setupPoolTokens.length; i++) {
            assetsIAsset[i] = IAsset(address(tokens[i]));
        }
        
        uint256[] memory minAmountsOut = new uint256[](setupPoolTokens.length);
        for (uint i = 0; i < setupPoolTokens.length; i++) {
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

    function swap(bytes32 poolId, address user, address assetIn, address assetOut, uint256 amount, uint256 limit, uint256 deadline, SwapKind kind) public {
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