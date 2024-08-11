// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "test/helpers/interfaces/ICreateX.sol";
import "forge-std/console.sol";

contract Constants {
    address public weth = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    address public wbtc = address(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);
    address public dai = address(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    address public composableStablePoolFactory = address(0x5B42eC6D40f7B7965BE5308c70e2603c0281C1E9);
    address public vault = address(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
    address public gaugeFactory = address(0x4E7bBd911cf1EFa442BC1b2e9Ea01ffE785412EC);

    constructor() {}
}
