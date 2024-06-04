// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "test/helpers/interfaces/ICreateX.sol";
import "forge-std/console.sol";


contract Constants {
    /// all chain
    ICreateX public constant createx = ICreateX(address(0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed)); // all chain

    address public immutable weth;
    address public immutable composableStablePoolFactory;
    address public immutable vault;
    

    constructor() {

        // if (block.chainid == 1) {
        weth = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2); // weth
        composableStablePoolFactory = address(0x5B42eC6D40f7B7965BE5308c70e2603c0281C1E9);
        vault = address(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
    }

}