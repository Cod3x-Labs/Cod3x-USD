// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "test/helpers/TestCdxUSDAndLendAndStaking.sol";

contract PidReserveInterestRateStrategyCdxUsdTest is TestCdxUSDAndLendAndStaking {
    address[] users;

    string path = "./test/foundry/facilitators/pid_tests/datas/output.csv";
    uint256 nbUsers = 4;
    uint256 initialAmt = 1e12 ether;
    uint256 DEFAULT_TIME_BEFORE_OP = 6 hours;
    int256 counterAssetPrice = int256(1 * 10 ** PRICE_FEED_DECIMALS);

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
            ERC20Mock(address(counterAsset)).approve(vault, type(uint256).max);
            ERC20Mock(address(cdxUsd)).approve(vault, type(uint256).max);
            vm.stopPrank();
        }

        /// file setup
        if (vm.exists(path)) vm.removeFile(path);
        vm.writeLine(
            path, "timestamp,user,action,asset,stablePoolBalance,currentVariableBorrowRate"
        );
    }

    function testTF() public view {
        console.log(
            "transferFunction == ",
            cdxUsdInterestRateStrategy.transferFunction(-400e24) / (1e27 / 10000)
        ); // bps
    }

    // 4 users  (users[0], users[1], users[2], users[3])
    // 4 tokens (wbtc, eth, dai, cdxUsd)
    // Initial Balancer Pool cdxUSD/CounterAsseter balance is 10M/10M.
    function testPid() public {
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
        console.log("cdxusd.balance = %18e", cdxusd.balanceOf(address(aTokens[3])));
        console.log("cdxUsdTreasury = %18e", cdxusd.balanceOf(cdxUsdTreasury));

        CdxUsdAToken(address(aTokens[3])).distributeFeesToTreasury();

        console.log("cdxusd.balance = %18e", cdxusd.balanceOf(address(aTokens[3])));
        console.log("cdxUsdTreasury = %18e", cdxusd.balanceOf(cdxUsdTreasury));

        // counterAssetPrice = int256(2 * 10 ** PRICE_FEED_DECIMALS); //! counter asset deppeg
    }
    // ------------------------------
    // ---------- Helpers -----------
    // ------------------------------

    function deposit(address user, ERC20 asset, uint256 amount) internal {
        vm.startPrank(user);
        asset.approve(address(deployedContracts.lendingPool), amount);
        deployedContracts.lendingPool.deposit(address(asset), true, amount, user);
        vm.stopPrank();
        logg(user, 0, address(asset));
        logCash();
        counterAssetPriceFeed.updateAnswer(counterAssetPrice); // needed to update the lastTimestamp.
        skip(DEFAULT_TIME_BEFORE_OP);
    }

    function borrow(address user, ERC20 asset, uint256 amount) internal {
        vm.startPrank(user);
        deployedContracts.lendingPool.borrow(address(asset), true, amount, user);
        vm.stopPrank();
        logg(user, 1, address(asset));
        logCash();
        counterAssetPriceFeed.updateAnswer(counterAssetPrice); // needed to update the lastTimestamp.
        skip(DEFAULT_TIME_BEFORE_OP);
    }

    function borrowWithoutSkip(address user, ERC20 asset, uint256 amount) internal {
        vm.startPrank(user);
        deployedContracts.lendingPool.borrow(address(asset), true, amount, user);
        vm.stopPrank();
        logCash();
        counterAssetPriceFeed.updateAnswer(counterAssetPrice); // needed to update the lastTimestamp.
        logg(user, 1, address(asset));
    }

    function withdraw(address user, ERC20 asset, uint256 amount) internal {
        vm.startPrank(user);
        deployedContracts.lendingPool.withdraw(address(asset), true, amount, user);
        vm.stopPrank();
        logg(user, 2, address(asset));
        logCash();
        counterAssetPriceFeed.updateAnswer(counterAssetPrice); // needed to update the lastTimestamp.
        skip(DEFAULT_TIME_BEFORE_OP);
    }

    function repay(address user, ERC20 asset, uint256 amount) internal {
        vm.startPrank(user);
        asset.approve(address(deployedContracts.lendingPool), amount);
        deployedContracts.lendingPool.repay(address(asset), true, amount, user);
        vm.stopPrank();
        logg(user, 3, address(asset));
        logCash();
        counterAssetPriceFeed.updateAnswer(counterAssetPrice); // needed to update the lastTimestamp.
        skip(DEFAULT_TIME_BEFORE_OP);
    }

    function plateau(uint256 period) public {
        for (uint256 i = 0; i < period; i++) {
            vm.startPrank(users[0]);
            deployedContracts.lendingPool.borrow(address(erc20Tokens[3]), true, 1, users[0]);
            vm.stopPrank();
            logg(users[0], 1, address(erc20Tokens[3]));
            counterAssetPriceFeed.updateAnswer(counterAssetPrice); // needed to update the lastTimestamp.
            skip(DEFAULT_TIME_BEFORE_OP);

            vm.startPrank(users[0]);
            erc20Tokens[3].approve(address(deployedContracts.lendingPool), 1);
            deployedContracts.lendingPool.repay(address(erc20Tokens[3]), true, 1, users[0]);
            vm.stopPrank();
            logg(users[0], 3, address(erc20Tokens[3]));
            counterAssetPriceFeed.updateAnswer(counterAssetPrice); // needed to update the lastTimestamp.
            skip(DEFAULT_TIME_BEFORE_OP);
        }
    }

    function swapBalancer(address user, ERC20 assetIn, uint256 amt) public {
        swap(
            poolId,
            user,
            address(assetIn),
            address(assetIn) == address(cdxUsd) ? address(counterAsset) : address(cdxUsd),
            amt,
            0,
            block.timestamp,
            SwapKind.GIVEN_IN
        );
    }

    function setManualInterestRate(uint256 manualInterestRate) public {
        cdxUsdInterestRateStrategy.setManualInterestRate(manualInterestRate);
    }

    function setErrI(int256 newErrI) public {
        cdxUsdInterestRateStrategy.setErrI(newErrI);
    }

    function logg(address user, uint256 action, address asset) public {
        (, uint256 currentVariableBorrowRate,) =
            cdxUsdInterestRateStrategy.getCurrentInterestRates();

        (uint256 cashCdxusd,,,) = IVault(vault).getPoolTokenInfo(poolId, cdxUsd);
        uint256 stablePoolBalance = cashCdxusd * 1e27 / INITIAL_CDXUSD_AMT;

        string memory data = string(
            abi.encodePacked(
                Strings.toString(block.timestamp),
                ",",
                Strings.toHexString(user),
                ",",
                Strings.toString(action),
                ",",
                Strings.toHexString(asset),
                ",",
                Strings.toString(stablePoolBalance), //!
                ",",
                Strings.toString(currentVariableBorrowRate)
            )
        );

        vm.writeLine(path, data);
    }

    function logCash() public view {
        (uint256 cashCdxusd,,,) = IVault(vault).getPoolTokenInfo(poolId, cdxUsd);
        (uint256 cashCa,,,) = IVault(vault).getPoolTokenInfo(poolId, IERC20(address(counterAsset)));

        // console.log("cash cdxUSD : ", cashCdxusd);
        // console.log("cash counter: ", cashCa);
        // console.log("---");
    }
}
