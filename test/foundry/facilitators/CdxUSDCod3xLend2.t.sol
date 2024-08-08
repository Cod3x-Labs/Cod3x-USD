// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

// Cod3x Lend
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ERC20} from "lib/Cod3x-Lend/contracts/dependencies/openzeppelin/contracts/ERC20.sol";
import "lib/Cod3x-Lend/contracts/protocol/libraries/helpers/Errors.sol";
import "lib/Cod3x-Lend/contracts/protocol/libraries/types/DataTypes.sol";
import {AToken} from "lib/Cod3x-Lend/contracts/protocol/tokenization/AToken.sol";
import {VariableDebtToken} from
    "lib/Cod3x-Lend/contracts/protocol/tokenization/VariableDebtToken.sol";

import {WadRayMath} from "lib/Cod3x-Lend/contracts/protocol/libraries/math/WadRayMath.sol";
import {MathUtils} from "lib/Cod3x-Lend/contracts/protocol/libraries/math/MathUtils.sol";
// import {ReserveBorrowConfiguration} from  "lib/Cod3x-Lend/contracts/protocol/libraries/configuration/ReserveConfiguration.sol";

// Balancer
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

import {TestCdxUSDAndLend} from "test/helpers/TestCdxUSDAndLend.sol";
import {ERC20Mock} from "../../helpers/mocks/ERC20Mock.sol";

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

// CdxUSD
import {CdxUSD} from "contracts/tokens/CdxUSD.sol";
import {CdxUsdIInterestRateStrategy} from
    "contracts/facilitators/cod3x_lend/interest_strategy/CdxUsdIInterestRateStrategy.sol";
import {CdxUsdOracle} from "contracts/facilitators/cod3x_lend/oracle/CdxUsdOracle.sol";
import {CdxUsdAToken} from "contracts/facilitators/cod3x_lend/token/CdxUsdAToken.sol";
import {CdxUsdVariableDebtToken} from
    "contracts/facilitators/cod3x_lend/token/CdxUsdVariableDebtToken.sol";
import {MockV3Aggregator} from "test/helpers/mocks/MockV3Aggregator.sol";

/// events
event Deposit(address indexed reserve, address user, address indexed onBehalfOf, uint256 amount);

event Withdraw(address indexed reserve, address indexed user, address indexed to, uint256 amount);

event Borrow(
    address indexed reserve,
    address user,
    address indexed onBehalfOf,
    uint256 amount,
    uint256 borrowRate
);

event Repay(address indexed reserve, address indexed user, address indexed repayer, uint256 amount);

contract TestCdxUSDCod3xLend2 is TestCdxUSDAndLend, ERC721Holder {
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
    uint256 public plateau = 10 days;
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
                RollingRewarder(ParentRollingRewarder(parentRewarder).createChild(address(cdxUsd)));
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

            // console.log(address(cod3xVault));
            // console.log(address(vault));
            // console.log(address(cdxUSD));
            // console.log(address(reliquary));
            // console.log(address(poolAdd));

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
                true,
                vault, // balancerVault,
                poolId,
                -80e25,
                1728000,
                13e19,
                owner
            );
            counterAssetPriceFeed =
                new MockV3Aggregator(counterAsset.decimals(), int256(1 * 10 ** PRICE_FEED_DECIMALS));
            cdxUsdInterestRateStrategy.setOracleValues(
                address(counterAssetPriceFeed), counterAsset.decimals(), 1e26, 86400
            );

            fixture_configureCdxUsd(
                address(deployedContracts.lendingPool),
                address(cdxUsdAToken),
                address(cdxUsdVariableDebtToken),
                address(cdxUsdOracle),
                address(cdxUsd),
                address(cdxUsdInterestRateStrategy),
                configAddresses,
                deployedContracts.lendingPoolConfigurator,
                deployedContracts.lendingPoolAddressesProvider
            );

            cdxUsd.addFacilitator(
                deployedContracts.lendingPool.getReserveData(address(cdxUsd), true).aTokenAddress,
                "Cod3x Lend",
                DEFAULT_CAPACITY
            );

            tokens.push(address(cdxUsd));
            erc20Tokens.push(ERC20(address(cdxUsd)));
            // console.log("Index: ", idx);
            (address _aTokenAddress,) = deployedContracts
                .protocolDataProvider
                .getReserveTokensAddresses(address(cdxUsd), true);
            aTokens.push(AToken(_aTokenAddress));
            (, address _variableDebtToken) = deployedContracts
                .protocolDataProvider
                .getReserveTokensAddresses(address(cdxUsd), true);
            variableDebtTokens.push(VariableDebtToken(_variableDebtToken));
        }

        // MAX approve "cod3xVault" by all users
        for (uint160 i = 1; i <= 3; i++) {
            vm.prank(address(i)); // address(0x1) == address(1)
            IERC20(poolAdd).approve(address(cod3xVault), type(uint256).max);
        }
    }

    // classical deposit/withdraw without cdxUSD
    function testDepositsAndWithdrawals(uint256 amount) public {
        address user = makeAddr("user");

        for (uint32 idx = 0; idx < aTokens.length - 1; idx++) {
            uint256 _userGrainBalanceBefore = aTokens[idx].balanceOf(address(user));
            uint256 _thisBalanceTokenBefore = erc20Tokens[idx].balanceOf(address(this));
            amount = bound(amount, 10_000, erc20Tokens[idx].balanceOf(address(this)));

            /* Deposit on behalf of user */
            erc20Tokens[idx].approve(address(deployedContracts.lendingPool), amount);
            vm.expectEmit(true, true, true, true);
            emit Deposit(address(erc20Tokens[idx]), address(this), user, amount);
            deployedContracts.lendingPool.deposit(address(erc20Tokens[idx]), true, amount, user);
            assertEq(_thisBalanceTokenBefore, erc20Tokens[idx].balanceOf(address(this)) + amount);
            assertEq(_userGrainBalanceBefore + amount, aTokens[idx].balanceOf(address(user)));

            /* User shall be able to withdraw underlying tokens */
            vm.startPrank(user);
            vm.expectEmit(true, true, true, true);
            emit Withdraw(address(erc20Tokens[idx]), user, user, amount);
            deployedContracts.lendingPool.withdraw(address(erc20Tokens[idx]), true, amount, user);
            vm.stopPrank();
            assertEq(amount, erc20Tokens[idx].balanceOf(user));
            assertEq(_userGrainBalanceBefore, aTokens[idx].balanceOf(address(this)));
        }
    }

    function testDaiBorrow() public {
        address user = makeAddr("user");
        uint256 amount = 1e18;

        uint256 _userAWethBalanceBefore = aTokens[1].balanceOf(address(user));
        uint256 _thisWethBalanceBefore = erc20Tokens[1].balanceOf(address(this));

        // Deposit weth on behalf of user
        erc20Tokens[1].approve(address(deployedContracts.lendingPool), amount);
        vm.expectEmit(true, true, true, true);
        emit Deposit(address(erc20Tokens[1]), address(this), user, amount);
        deployedContracts.lendingPool.deposit(address(erc20Tokens[1]), true, amount, user);

        assertEq(_thisWethBalanceBefore, erc20Tokens[1].balanceOf(address(this)) + amount);
        assertEq(_userAWethBalanceBefore + amount, aTokens[1].balanceOf(address(user)));

        // Deposit dai on behalf of user
        erc20Tokens[2].approve(address(deployedContracts.lendingPool), type(uint256).max);
        deployedContracts.lendingPool.deposit(address(erc20Tokens[2]), true, 10000e18, user);

        // Borrow/Mint cdxUSD
        uint256 amountMintDai = 1000e18;
        vm.startPrank(user);
        deployedContracts.lendingPool.borrow(address(erc20Tokens[2]), true, amountMintDai, user);
        uint256 balanceUserBefore = erc20Tokens[2].balanceOf(user);
        assertEq(amountMintDai, balanceUserBefore);
        (uint256 totalCollateralETH, uint256 totalDebtETH,,,, uint256 healthFactor1) =
            deployedContracts.lendingPool.getUserAccountData(user);
        console.log("totalCollateralETH = ", totalCollateralETH);
        console.log("totalDebtETH = ", totalDebtETH);
        console.log("getReservesCount = ", deployedContracts.lendingPool.getReservesCount());

        vm.startPrank(user);
        erc20Tokens[2].approve(address(deployedContracts.lendingPool), type(uint256).max);
        deployedContracts.lendingPool.repay(address(erc20Tokens[2]), true, amountMintDai / 2, user);
        (,,,,, uint256 healthFactor2) = deployedContracts.lendingPool.getUserAccountData(user);
        assertGt(healthFactor2, healthFactor1);
        assertGt(balanceUserBefore, cdxUsd.balanceOf(user));
    }

    function testCdxUsdBorrow() public {
        address user = makeAddr("user");
        uint256 amount = 1e18;

        uint256 _userAWethBalanceBefore = aTokens[1].balanceOf(address(user));
        uint256 _thisWethBalanceBefore = erc20Tokens[1].balanceOf(address(this));

        // Deposit weth on behalf of user
        erc20Tokens[1].approve(address(deployedContracts.lendingPool), amount);
        vm.expectEmit(true, true, true, true);
        emit Deposit(address(erc20Tokens[1]), address(this), user, amount);
        deployedContracts.lendingPool.deposit(address(erc20Tokens[1]), true, amount, user);

        assertEq(_thisWethBalanceBefore, erc20Tokens[1].balanceOf(address(this)) + amount);
        assertEq(_userAWethBalanceBefore + amount, aTokens[1].balanceOf(address(user)));

        // Borrow/Mint cdxUSD
        uint256 amountMintCdxUsd = 1000e18;
        vm.startPrank(user);
        deployedContracts.lendingPool.borrow(address(cdxUsd), true, amountMintCdxUsd, user);
        uint256 balanceUserBefore = cdxUsd.balanceOf(user);
        assertEq(amountMintCdxUsd, balanceUserBefore);
        (uint256 totalCollateralETH, uint256 totalDebtETH,,,, uint256 healthFactor1) =
            deployedContracts.lendingPool.getUserAccountData(user);

        vm.startPrank(user);
        cdxUsd.approve(address(deployedContracts.lendingPool), type(uint256).max);
        deployedContracts.lendingPool.repay(address(cdxUsd), true, amountMintCdxUsd / 2, user);
        (,,,,, uint256 healthFactor2) = deployedContracts.lendingPool.getUserAccountData(user);
        assertGt(healthFactor2, healthFactor1);
        assertGt(balanceUserBefore, cdxUsd.balanceOf(user));
    }

    function testBorrowRepay() public {
        address user = makeAddr("user");

        ERC20 dai = erc20Tokens[2];
        ERC20 wbtc = erc20Tokens[1];
        uint256 daiDepositAmount = 5000e18; /* $5k */ // consider fuzzing here

        uint256 wbtcPrice = oracle.getAssetPrice(address(wbtc));
        uint256 daiPrice = oracle.getAssetPrice(address(dai));
        uint256 daiDepositValue = daiDepositAmount * daiPrice / (10 ** PRICE_FEED_DECIMALS);
        (, uint256 daiLtv,,,,,,,) =
            deployedContracts.protocolDataProvider.getReserveConfigurationData(address(dai), true);
        uint256 wbtcMaxBorrowAmountWithDaiCollateral;
        {
            uint256 daiMaxBorrowValue = daiLtv * daiDepositValue / 10_000;

            uint256 wbtcMaxBorrowAmountRay = daiMaxBorrowValue.rayDiv(wbtcPrice);
            wbtcMaxBorrowAmountWithDaiCollateral = fixture_preciseConvertWithDecimals(
                wbtcMaxBorrowAmountRay, dai.decimals(), wbtc.decimals()
            );
            // (daiMaxBorrowValue * 10 ** PRICE_FEED_DECIMALS) / wbtcPrice;
        }
        require(
            wbtc.balanceOf(address(this)) > wbtcMaxBorrowAmountWithDaiCollateral, "Too less wbtc"
        );
        uint256 wbtcDepositAmount = wbtcMaxBorrowAmountWithDaiCollateral * 15 / 10;

        /* Main user deposits Dai and wants to borrow */
        dai.approve(address(deployedContracts.lendingPool), daiDepositAmount);
        deployedContracts.lendingPool.deposit(address(dai), true, daiDepositAmount, address(this));

        /* Other user deposits wbtc thanks to that there is enough funds to borrow */
        wbtc.approve(address(deployedContracts.lendingPool), wbtcDepositAmount);
        deployedContracts.lendingPool.deposit(address(wbtc), true, wbtcDepositAmount, user);

        uint256 wbtcBalanceBeforeBorrow = wbtc.balanceOf(address(this));

        (,,,, uint256 reserveFactors,,,,) =
            deployedContracts.protocolDataProvider.getReserveConfigurationData(address(wbtc), true);
        (, uint256 expectedBorrowRate) = deployedContracts.volatileStrategy.calculateInterestRates(
            address(wbtc),
            address(aTokens[1]),
            0,
            wbtcMaxBorrowAmountWithDaiCollateral,
            wbtcMaxBorrowAmountWithDaiCollateral,
            reserveFactors
        );

        /* Main user borrows maxPossible amount of wbtc */
        vm.expectEmit(true, true, true, true);
        emit Borrow(
            address(wbtc),
            address(this),
            address(this),
            wbtcMaxBorrowAmountWithDaiCollateral,
            expectedBorrowRate
        );
        deployedContracts.lendingPool.borrow(
            address(wbtc), true, wbtcMaxBorrowAmountWithDaiCollateral, address(this)
        );
        /* Main user's balance should be: initial amount + borrowed amount */
        assertEq(
            wbtcBalanceBeforeBorrow + wbtcMaxBorrowAmountWithDaiCollateral,
            wbtc.balanceOf(address(this))
        );

        /* Main user repays his debt */
        wbtc.approve(address(deployedContracts.lendingPool), wbtcMaxBorrowAmountWithDaiCollateral);
        vm.expectEmit(true, true, true, true);
        emit Repay(
            address(wbtc), address(this), address(this), wbtcMaxBorrowAmountWithDaiCollateral
        );
        deployedContracts.lendingPool.repay(
            address(wbtc), true, wbtcMaxBorrowAmountWithDaiCollateral, address(this)
        );
        /* Main user's balance should be the same as before borrowing */
        assertEq(wbtcBalanceBeforeBorrow, wbtc.balanceOf(address(this)));
    }
}
