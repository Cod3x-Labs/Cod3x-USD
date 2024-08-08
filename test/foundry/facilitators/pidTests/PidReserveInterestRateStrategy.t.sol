// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "test/helpers/TestCdxUSDAndLendAndStaking.sol";
// import "lib/Cod3x-Lend/contracts/protocol/libraries/helpers/Errors.sol";
// import {WadRayMath} from "lib/Cod3x-Lend/contracts/protocol/libraries/math/WadRayMath.sol";
// import
//     "lib/Cod3x-Lend/contracts/protocol/lendingpool/interestRateStrategies/PidReserveInterestRateStrategy.sol";
// import "contracts/facilitators/cod3x_lend/interest_strategy/CdxUsdIInterestRateStrategy.sol";
// import {Strings} from "openzeppelin-contracts/contracts/utils/Strings.sol";

contract PidReserveInterestRateStrategyCdxUsdTest is TestCdxUSDAndLendAndStaking {
    // using WadRayMath for uint256;

    address[] users;

    string path = "./test/foundry/facilitators/pidTests/datas/output.csv";
    uint256 nbUsers = 4;
    uint256 initialAmt = 1e12 ether;
    uint256 DEFAULT_TIME_BEFORE_OP = 6 hours;

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
            path,
            "timestamp,user,action,asset,utilizationRate,currentLiquidityRate,currentVariableBorrowRate"
        );
    }

    function testTF() public view {
        console.log(
            "transferFunction == ",
            cdxUsdInterestRateStrategy.transferFunction(-400e24) / (1e27 / 10000)
        ); // bps
    }

    // 4 users  (users[0], users[1], users[2], users[3])
    // 3 tokens (wbtc, eth, dai)
    function testPid() public {
        ERC20 wbtc = erc20Tokens[0]; // wbtcPrice =  670000,0000000$
        ERC20 eth = erc20Tokens[1]; // ethPrice =  3700,00000000$
        ERC20 dai = erc20Tokens[2]; // daiPrice =  1,00000000$
        ERC20 cdxusd = erc20Tokens[3]; // daiPrice =  1,00000000$

        deposit(users[0], wbtc, 2e8);
        deposit(users[1], wbtc, 20_000e8);
        deposit(users[1], dai, 100_000e18);

        borrow(users[1], cdxusd, 9_000_000e18);
        plateau(200);
        borrow(users[1], cdxusd, 500e18);
        swapBalancer(users[1], cdxusd, 9_000_000e18);
        plateau(200);
        repay(users[1], cdxusd, 500e18);
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
        skip(DEFAULT_TIME_BEFORE_OP);
    }

    function borrow(address user, ERC20 asset, uint256 amount) internal {
        vm.startPrank(user);
        deployedContracts.lendingPool.borrow(address(asset), true, amount, user);
        vm.stopPrank();
        logg(user, 1, address(asset));
        skip(DEFAULT_TIME_BEFORE_OP);
    }

    function borrowWithoutSkip(address user, ERC20 asset, uint256 amount) internal {
        vm.startPrank(user);
        deployedContracts.lendingPool.borrow(address(asset), true, amount, user);
        vm.stopPrank();
        logg(user, 1, address(asset));
    }

    function withdraw(address user, ERC20 asset, uint256 amount) internal {
        vm.startPrank(user);
        deployedContracts.lendingPool.withdraw(address(asset), true, amount, user);
        vm.stopPrank();
        logg(user, 2, address(asset));
        skip(DEFAULT_TIME_BEFORE_OP);
    }

    function repay(address user, ERC20 asset, uint256 amount) internal {
        vm.startPrank(user);
        asset.approve(address(deployedContracts.lendingPool), amount);
        deployedContracts.lendingPool.repay(address(asset), true, amount, user);
        vm.stopPrank();
        logg(user, 3, address(asset));
        skip(DEFAULT_TIME_BEFORE_OP);
    }

    function plateau(uint256 period) public {
        for (uint256 i = 0; i < period; i++) {
            borrow(users[0], erc20Tokens[3], 1);
            repay(users[0], erc20Tokens[3], 1);
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

    function logg(address user, uint256 action, address asset) public {
        (uint256 currentLiquidityRate, uint256 currentVariableBorrowRate, uint256 utilizationRate) =
            cdxUsdInterestRateStrategy.getCurrentInterestRates();

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
                Strings.toString(utilizationRate),
                ",",
                Strings.toString(currentLiquidityRate),
                ",",
                Strings.toString(currentVariableBorrowRate)
            )
        );

        vm.writeLine(path, data);
    }
}
