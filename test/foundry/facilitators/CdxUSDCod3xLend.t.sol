// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./Common.sol";
import "lib/Cod3x-Lend/contracts/protocol/libraries/helpers/Errors.sol";
import {WadRayMath} from "lib/Cod3x-Lend/contracts/protocol/libraries/math/WadRayMath.sol";
import {MathUtils} from "lib/Cod3x-Lend/contracts/protocol/libraries/math/MathUtils.sol";
import "lib/Cod3x-Lend/contracts/protocol/libraries/configuration/ReserveConfiguration.sol";

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
import {CdxUSD} from "contracts/tokens/CdxUSD.sol";
import {CdxUsdIInterestRateStrategy} from
    "contracts/facilitators/cod3x_lend/interest_strategy/CdxUsdIInterestRateStrategy.sol";
import {CdxUsdOracle} from "contracts/facilitators/cod3x_lend/oracle/CdxUsdOracle.sol";
import {CdxUsdAToken} from "contracts/facilitators/cod3x_lend/token/CdxUsdAToken.sol";
import {CdxUsdVariableDebtToken} from
    "contracts/facilitators/cod3x_lend/token/CdxUsdVariableDebtToken.sol";

// reliquary
import "contracts/staking_module/reliquary/Reliquary.sol";
import "contracts/staking_module/reliquary/interfaces/IReliquary.sol";
import "contracts/staking_module/reliquary/nft_descriptors/NFTDescriptor.sol";
import "contracts/staking_module/reliquary/curves/LinearPlateauCurve.sol";
import "contracts/staking_module/reliquary/rewarders/RollingRewarder.sol";
import "contracts/staking_module/reliquary/rewarders/ParentRollingRewarder.sol";
import "contracts/staking_module/reliquary/interfaces/ICurves.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

// vault
import {ReaperBaseStrategyv4} from "lib/Cod3x-Vault/src/ReaperBaseStrategyv4.sol";
import {ReaperVaultV2} from "lib/Cod3x-Vault/src/ReaperVaultV2.sol";
import {ScdxUsdVaultStrategy} from
    "contracts/staking_module/vault_strategy/ScdxUsdVaultStrategy.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "lib/Cod3x-Vault/test/vault/mock/FeeControllerMock.sol";
import "contracts/staking_module/vault_strategy/libraries/BalancerHelper.sol";

contract TestCdxUSDCod3xLend is Common {
    using WadRayMath for uint256;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using ReserveBorrowConfiguration for DataTypes.ReserveBorrowConfigurationMap;

    ERC20[] erc20Tokens;
    DeployedContracts deployedContracts;
    ConfigAddresses configAddresses;

    CdxUSD public cdxUsd;
    CdxUsdIInterestRateStrategy public cdxUsdInterestRateStrategy;
    CdxUsdOracle public cdxUsdOracle;
    CdxUsdAToken public cdxUsdAToken;
    CdxUsdVariableDebtToken public cdxUsdVariableDebtToken;

    event Deposit(
        address indexed reserve, address user, address indexed onBehalfOf, uint256 amount
    );
    event Withdraw(
        address indexed reserve, address indexed user, address indexed to, uint256 amount
    );
    event Borrow(
        address indexed reserve,
        address user,
        address indexed onBehalfOf,
        uint256 amount,
        uint256 borrowRate
    );
    event Repay(
        address indexed reserve, address indexed user, address indexed repayer, uint256 amount
    );

    uint32 aEid = 1;
    uint32 bEid = 2;
    uint128 public constant DEFAULT_CAPACITY = 100_000_000e18;
    uint128 public constant INITIAL_AMT = 1_000_000e18;
    uint128 public constant INITIAL_CDXUSD_AMT = 10_000_000e18;
    uint128 public constant INITIAL_COUNTER_ASSET_AMT = 10_000_000e18;

    address public userA = address(0x1);
    address public owner = address(this);
    address public guardian = address(0x4);
    address public treasury = address(0x5);

    address public balancerVault;
    bytes32 public poolId;
    address public counterAssetPriceFeed;
    address public counterAsset;

    address public balancerPoolAdd;
    IERC20[] public balancerPoolAssets;
    IReliquary public reliquary;
    RollingRewarder public rewarder;
    ReaperVaultV2 public cod3xVault;
    ScdxUsdVaultStrategy public strategy;
    IERC20 public mockRewardToken;

    uint256 public indexCdxUsd;
    uint256 public indexCounterAsset;

    // Linear function config (to config)
    uint256 public slope = 100; // Increase of multiplier every second
    uint256 public minMultiplier = 365 days * 100; // Arbitrary (but should be coherent with slope)
    uint256 public plateau = 10 days;
    uint256 private constant RELIC_ID = 1;

    function setUp() public override {
        super.setUp();

        opFork = vm.createSelectFork(RPC, FORK_BLOCK);
        assertEq(vm.activeFork(), opFork);

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
            vm.startPrank(userA);
            cdxUsd.mint(address(this), INITIAL_AMT);
            cdxUSD.mint(userA, INITIAL_CDXUSD_AMT);
            vm.stopPrank();
        }

        /// ======= Counter Asset deployments =======
        {
            indexCounterAsset = address(new ERC20Mock{salt: "1"}(18));
            ERC20Mock(indexCounterAsset).mint(userA, INITIAL_COUNTER_ASSET_AMT);
        }

        /// ======= Cod3x Lend deploy =======
        {
            deployedContracts = fixture_deployProtocol();
            configAddresses = ConfigAddresses(
                address(deployedContracts.protocolDataProvider),
                address(deployedContracts.stableStrategy),
                address(deployedContracts.volatileStrategy),
                address(deployedContracts.treasury),
                address(deployedContracts.rewarder),
                address(deployedContracts.aTokensAndRatesHelper)
            );
            fixture_configureProtocol(
                address(deployedContracts.lendingPool),
                address(aToken),
                configAddresses,
                deployedContracts.lendingPoolConfigurator,
                deployedContracts.lendingPoolAddressesProvider
            );
            mockedVaults = fixture_deployErc4626Mocks(tokens, address(deployedContracts.treasury));
            erc20Tokens = fixture_getErc20Tokens(tokens);
            fixture_transferTokensToTestContract(erc20Tokens, INITIAL_AMT, address(this));
        }
        /// ======= Balancer Pool Deploy =======
        {
            balancerPoolAssets = [IERC20(address(cdxUSD)), IERC20(counterAsset)];

            // balancer stable pool creation
            (poolId, balancerPoolAdd) = createStablePool(balancerPoolAssets, 2500, userA);

            // join Pool
            (IERC20[] memory setupPoolTokens,,) = IVault(vault).getPoolTokens(poolId);

            uint256 indexCdxUsdTemp;
            uint256 indexCounterAssetTemp;
            uint256 indexBtpTemp;
            for (uint256 i = 0; i < setupPoolTokens.length; i++) {
                if (setupPoolTokens[i] == IERC20(address(cdxUSD))) indexCdxUsdTemp = i;
                if (setupPoolTokens[i] == IERC20(counterAsset)) indexCounterAssetTemp = i;
                if (setupPoolTokens[i] == IERC20(balancerPoolAdd)) indexBtpTemp = i;
            }

            uint256[] memory amountsToAdd = new uint256[](setupPoolTokens.length);
            amountsToAdd[indexCdxUsdTemp] = INITIAL_CDXUSD_AMT;
            amountsToAdd[indexCounterAssetTemp] = INITIAL_COUNTER_ASSET_AMT;
            amountsToAdd[indexBtpTemp] = 0;

            joinPool(poolId, setupPoolTokens, amountsToAdd, userA, JoinKind.INIT);

            vm.prank(userA);
            IERC20(balancerPoolAdd).transfer(address(this), 1);

            IERC20[] memory setupPoolTokensWithoutBTP =
                BalancerHelper._dropBptItem(setupPoolTokens, balancerPoolAdd);

            for (uint256 i = 0; i < setupPoolTokensWithoutBTP.length; i++) {
                if (setupPoolTokensWithoutBTP[i] == IERC20(address(cdxUSD))) indexCdxUsd = i;
                if (setupPoolTokensWithoutBTP[i] == IERC20(counterAsset)) indexCounterAsset = i;
            }
        }

        /// ======= cdxUSD Cod3x Lend dependencies deploy =======
        // {
        //     cdxUsdAToken = new CdxUsdAToken();
        //     cdxUsdVariableDebtToken = new CdxUsdVariableDebtToken();
        //     cdxUsdOracle = new CdxUsdOracle();
        //     cdxUsdInterestRateStrategy = new CdxUsdIInterestRateStrategy(
        //         address(deployedContracts.lendingPoolAddressesProvider),
        //         address(cdxUsd),
        //         true,
        //         balancerVault,
        //         poolId,
        //         -80e25,
        //         1728000,
        //         13e19,
        //         owner
        //     );
        //     cdxUsdInterestRateStrategy.setOracleValues(counterAssetPriceFeed, 18, 1e26, 86400);
        // }
    }

    function testDepositsAndWithdrawals(uint256 amount) public {
        address user = makeAddr("user");
    }
}
