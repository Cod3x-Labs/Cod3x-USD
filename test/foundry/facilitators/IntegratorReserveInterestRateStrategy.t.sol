// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "test/helpers/TestCdxUSDAndLendAndStaking.sol";

contract IntegratorReserveInterestRateStrategy is TestCdxUSDAndLendAndStaking {
    address[] users;

    string path = "./test/foundry/facilitators/pid_tests/datas/output.csv";
    uint256 nbUsers = 4;
    uint256 initialAmt = 1e12 ether;
    uint256 DEFAULT_TIME_BEFORE_OP = 6 hours;
    int256 counterAssetPrice = int256(1 * 10 ** PRICE_FEED_DECIMALS);

    ERC20 wbtcEr20; // wbtcPrice =  670000,0000000$
    ERC20 ethErc220; // ethPrice =  3700,00000000$
    ERC20 daiErc20; // daiPrice =  1,00000000$
    ERC20 cdxUsdErc20; // cdxUsdPrice =  1,00000000$

    int256 ONE = int256(1 * 10 ** PRICE_FEED_DECIMALS);
    int256 RAY = int256(1e27);

    // 4 users  (users[0], users[1], users[2], users[3])
    // 4 tokens (wbtc, eth, dai, cdxUsd)
    // Initial Balancer Pool cdxUSD/CounterAsseter balance is 10M/10M.
    function setUp() public override {
        super.setUp();

        /// users
        for (uint256 i = 0; i < nbUsers; i++) {
            users.push(vm.addr(i + 1));
            for (uint256 j = 0; j < erc20Tokens.length; j++) {
                if (address(erc20Tokens[j]) != address(cdxUsd)) {
                    deal(address(erc20Tokens[j]), users[i], initialAmt);
                }
            }
        }

        /// Mint counter asset and approve Balancer vault
        for (uint256 i = 0; i < nbUsers; i++) {
            ERC20Mock(address(counterAsset)).mint(users[i], initialAmt);
            vm.startPrank(users[i]);
            ERC20Mock(address(counterAsset)).approve(address(tRouter), type(uint256).max);
            ERC20Mock(address(cdxUsd)).approve(address(tRouter), type(uint256).max);
            ERC20(address(poolAdd)).approve(address(tRouter), type(uint256).max);
            vm.stopPrank();
        }

        ERC20Mock(address(counterAsset)).approve(address(tRouter), type(uint256).max);
        ERC20Mock(address(cdxUsd)).approve(address(tRouter), type(uint256).max);
        ERC20(address(poolAdd)).approve(address(tRouter), type(uint256).max);

        wbtcEr20 = erc20Tokens[0]; // wbtcPrice =  670000,0000000$
        ethErc220 = erc20Tokens[1]; // ethPrice =  3700,00000000$
        daiErc20 = erc20Tokens[2]; // daiPrice =  1,00000000$
        cdxUsdErc20 = erc20Tokens[3]; // cdxUsdPrice =  1,00000000$
    }

    function testInterestRateIncrease() public {
        deposit(users[0], wbtcEr20, 2e8);
        deposit(users[1], wbtcEr20, 20_000e8);
        deposit(users[1], daiErc20, 100_000e18);

        borrow(users[1], cdxUsdErc20, 9_000_000e18);
        (, uint256 currentVariableBorrowRateBefore,) =
            cdxUsdInterestRateStrategy.getCurrentInterestRates();

        swapBalancer(users[1], cdxUsdErc20, 2_000_000e18);
        plateau(20);
        (, uint256 currentVariableBorrowRateAfter,) =
            cdxUsdInterestRateStrategy.getCurrentInterestRates();

        assertGt(currentVariableBorrowRateAfter, currentVariableBorrowRateBefore);
    }

    function testInterestRateDecrease() public {
        deposit(users[0], wbtcEr20, 2e8);
        deposit(users[1], wbtcEr20, 20_000e8);
        deposit(users[1], daiErc20, 100_000e18);

        borrow(users[1], cdxUsdErc20, 9_000_000e18);
        (, uint256 currentVariableBorrowRateBefore,) =
            cdxUsdInterestRateStrategy.getCurrentInterestRates();

        swapBalancer(users[1], counterAsset, 2_000_000e18);
        plateau(20);
        (, uint256 currentVariableBorrowRateAfter,) =
            cdxUsdInterestRateStrategy.getCurrentInterestRates();

        counterAssetPriceFeed.updateAnswer(int256(1 * 10 ** PRICE_FEED_DECIMALS));

        assertLt(currentVariableBorrowRateAfter, currentVariableBorrowRateBefore);
    }

    function testCounterAssetDeppegIncrease(uint256 priceSeed) public {
        int256 price_ = int256(bound(priceSeed, 1, uint256(ONE * 2)));

        deposit(users[0], wbtcEr20, 2e8);
        deposit(users[1], wbtcEr20, 20_000e8);
        deposit(users[1], daiErc20, 100_000e18);

        borrow(users[1], cdxUsdErc20, 9_000_000e18);
        (, uint256 currentVariableBorrowRateBefore,) =
            cdxUsdInterestRateStrategy.getCurrentInterestRates();

        counterAssetPriceFeed.updateAnswer(price_);

        swapBalancer(users[1], cdxUsdErc20, 2_000_000e18);
        plateau(20);
        (, uint256 currentVariableBorrowRateAfter,) =
            cdxUsdInterestRateStrategy.getCurrentInterestRates();

        if (price_ > ONE * 11e26 / RAY || price_ < ONE * 9e26 / RAY) {
            assertEq(currentVariableBorrowRateAfter, currentVariableBorrowRateBefore);
        } else if (price_ < ONE * 11e26 / RAY && price_ > ONE * 9e26 / RAY) {
            assertGt(currentVariableBorrowRateAfter, currentVariableBorrowRateBefore);
        }
    }

    function testCounterAssetDeppegDecrease(uint256 priceSeed) public {
        int256 price_ = int256(bound(priceSeed, 1, uint256(ONE * 2)));

        deposit(users[0], wbtcEr20, 2e8);
        deposit(users[1], wbtcEr20, 20_000e8);
        deposit(users[1], daiErc20, 100_000e18);

        borrow(users[1], cdxUsdErc20, 9_000_000e18);
        (, uint256 currentVariableBorrowRateBefore,) =
            cdxUsdInterestRateStrategy.getCurrentInterestRates();

        counterAssetPriceFeed.updateAnswer(price_);

        console2.log("balanceOf user1 ::::: ", counterAsset.balanceOf(users[1]));

        swapBalancer(users[1], counterAsset, 2_000_000e18);
        plateau(20);
        (, uint256 currentVariableBorrowRateAfter,) =
            cdxUsdInterestRateStrategy.getCurrentInterestRates();

        if (price_ > ONE * 11e26 / RAY || price_ < ONE * 9e26 / RAY) {
            assertEq(currentVariableBorrowRateAfter, currentVariableBorrowRateBefore);
        } else if (price_ < ONE * 11e26 / RAY && price_ > ONE * 9e26 / RAY) {
            assertLt(currentVariableBorrowRateAfter, currentVariableBorrowRateBefore);
        }
    }

    function testManuelInterestRate() public {
        deposit(users[0], wbtcEr20, 2e8);
        deposit(users[1], wbtcEr20, 20_000e8);
        deposit(users[1], daiErc20, 100_000e18);

        borrow(users[1], cdxUsdErc20, 9_000_000e18);
        setManualInterestRate(1e27);

        (, uint256 currentVariableBorrowRateBefore,) =
            cdxUsdInterestRateStrategy.getCurrentInterestRates();

        swapBalancer(users[1], counterAsset, 2_000_000e18);
        plateau(20);
        (, uint256 currentVariableBorrowRateAfter,) =
            cdxUsdInterestRateStrategy.getCurrentInterestRates();

        assertEq(currentVariableBorrowRateAfter, currentVariableBorrowRateBefore);
    }

    function testSetErrI() public {
        deposit(users[0], wbtcEr20, 2e8);
        deposit(users[1], wbtcEr20, 20_000e8);
        deposit(users[1], daiErc20, 100_000e18);

        borrow(users[1], cdxUsdErc20, 9_000_000e18);
        (, uint256 currentVariableBorrowRateBefore,) =
            cdxUsdInterestRateStrategy.getCurrentInterestRates();

        setErrI(1e25);

        (, uint256 currentVariableBorrowRateAfter,) =
            cdxUsdInterestRateStrategy.getCurrentInterestRates();

        assertLt(currentVariableBorrowRateAfter, currentVariableBorrowRateBefore);
    }

    function testDistributeFeesToTreasury() public {
        ERC20 wbtc = erc20Tokens[0]; // wbtcPrice =  670000,0000000$
        ERC20 eth = erc20Tokens[1]; // ethPrice =  3700,00000000$
        ERC20 dai = erc20Tokens[2]; // daiPrice =  1,00000000$
        ERC20 cdxusd = erc20Tokens[3]; // cdxUsdPrice =  1,00000000$

        deposit(users[0], wbtc, 2e8);
        deposit(users[1], wbtc, 20_000e8);
        deposit(users[1], dai, 100_000e18);

        borrow(users[1], cdxusd, 9_000_000e18);

        plateau(20);
        swapBalancer(users[1], cdxusd, 2_000_000e18);
        plateau(20);
        plateau(20);
        swapBalancer(users[1], counterAsset, 1_000_000e18);
        plateau(20);
        swapBalancer(users[1], counterAsset, 200_000e18);
        plateau(20);
        setManualInterestRate(1e27 / 50); // 2%
        swapBalancer(users[1], counterAsset, 200_000e18);
        plateau(20);
        plateau(20);
        swapBalancer(users[1], counterAsset, 1_200_000e18);
        plateau(20);
        setManualInterestRate(0); // stop
        setErrI(13e25 * 2);
        swapBalancer(users[1], counterAsset, 200_000e18);
        plateau(20);
        plateau(20);
        swapBalancer(users[1], counterAsset, 1_200_000e18);
        plateau(20);

        repay(users[1], cdxusd, 100_000e18);

        uint256 balanceCdxUsdATokenBefore = cdxusd.balanceOf(address(commonContracts.aTokens[3]));
        uint256 bpsReliquaryAlloc =
            CdxUsdAToken(address(commonContracts.aTokens[3]))._reliquaryAllocation();

        assertGt(balanceCdxUsdATokenBefore, 0);
        assertEq(cdxusd.balanceOf(extContracts.treasury), 0);

        CdxUsdAToken(address(commonContracts.aTokens[3])).distributeFeesToTreasury();

        assertEq(cdxusd.balanceOf(address(commonContracts.aTokens[3])), 0);
        assertEq(
            cdxusd.balanceOf(extContracts.treasury),
            balanceCdxUsdATokenBefore - bpsReliquaryAlloc * balanceCdxUsdATokenBefore / 10000
        );
    }

    // ------------------------------
    // ---------- Helpers -----------
    // ------------------------------

    function deposit(address user, ERC20 asset, uint256 amount) internal {
        vm.startPrank(user);
        asset.approve(address(deployedContracts.lendingPool), amount);
        deployedContracts.lendingPool.deposit(
            address(asset), address(asset) == address(cdxUsd) ? false : true, amount, user
        );
        vm.stopPrank();
        logg();
        skip(DEFAULT_TIME_BEFORE_OP);
    }

    function borrow(address user, ERC20 asset, uint256 amount) internal {
        vm.startPrank(user);
        deployedContracts.lendingPool.borrow(
            address(asset), address(asset) == address(cdxUsd) ? false : true, amount, user
        );
        vm.stopPrank();
        logg();
        skip(DEFAULT_TIME_BEFORE_OP);
    }

    function borrowWithoutSkip(address user, ERC20 asset, uint256 amount) internal {
        vm.startPrank(user);
        deployedContracts.lendingPool.borrow(
            address(asset), address(asset) == address(cdxUsd) ? false : true, amount, user
        );
        vm.stopPrank();
        logg();
    }

    function withdraw(address user, ERC20 asset, uint256 amount) internal {
        vm.startPrank(user);
        deployedContracts.lendingPool.withdraw(
            address(asset), address(asset) == address(cdxUsd) ? false : true, amount, user
        );
        vm.stopPrank();
        logg();
        skip(DEFAULT_TIME_BEFORE_OP);
    }

    function repay(address user, ERC20 asset, uint256 amount) internal {
        vm.startPrank(user);
        asset.approve(address(deployedContracts.lendingPool), amount);
        deployedContracts.lendingPool.repay(
            address(asset), address(asset) == address(cdxUsd) ? false : true, amount, user
        );
        vm.stopPrank();
        logg();
        skip(DEFAULT_TIME_BEFORE_OP);
    }

    function plateau(uint256 period) public {
        for (uint256 i = 0; i < period; i++) {
            vm.startPrank(users[0]);
            deployedContracts.lendingPool.borrow(
                address(erc20Tokens[3]),
                address(erc20Tokens[3]) == address(cdxUsd) ? false : true,
                1,
                users[0]
            );
            vm.stopPrank();
            skip(DEFAULT_TIME_BEFORE_OP);

            vm.startPrank(users[0]);
            erc20Tokens[3].approve(address(deployedContracts.lendingPool), 1);
            deployedContracts.lendingPool.repay(
                address(erc20Tokens[3]),
                address(erc20Tokens[3]) == address(cdxUsd) ? false : true,
                1,
                users[0]
            );
            vm.stopPrank();
            skip(DEFAULT_TIME_BEFORE_OP);
        }
    }

    function swapBalancer(address user, ERC20 assetIn, uint256 amt) public {
        vm.startPrank(user);
        tRouter.swapSingleTokenExactIn(
            poolAdd,
            IERC20(address(assetIn)),
            address(assetIn) == address(cdxUsd)
                ? IERC20(address(counterAsset))
                : IERC20(address(cdxUsd)),
            amt,
            0
        );
        vm.stopPrank();
    }

    function setManualInterestRate(uint256 manualInterestRate) public {
        cdxUsdInterestRateStrategy.setManualInterestRate(manualInterestRate);
    }

    function setErrI(int256 newErrI) public {
        cdxUsdInterestRateStrategy.setErrI(newErrI);
    }

    function logg() public view {
        // (uint256 cashCdxusd,,,) = IVault(vault).getPoolTokenInfo(poolId, cdxUsd);
        // (uint256 cashCa,,,) = IVault(vault).getPoolTokenInfo(poolId, IERC20(address(counterAsset)));
        // (, uint256 currentVariableBorrowRate,) =
        //     cdxUsdInterestRateStrategy.getCurrentInterestRates();
        // uint256 stablePoolBalance = cashCdxusd * 1e27 / INITIAL_CDXUSD_AMT;

        // console2.log("stablePoolBalance : ", stablePoolBalance);
        // console2.log("currentVariableBorrowRate : ", currentVariableBorrowRate);
        // console2.log("cash cdxUSD : ", cashCdxusd);
        // console2.log("cash counter: ", cashCa);
        // console2.log("---");
    }
}
