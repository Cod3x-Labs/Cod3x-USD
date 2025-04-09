// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script, console2} from "forge-std/Script.sol";
import "forge-std/console2.sol";
import "./Constants.sol";
import "contracts/tokens/CdxUSD.sol";

contract CdxUsdGetBytecode is Script, Constants {
    string public name = "Cod3x USD";
    string public symbol = "cdxUSD";
    address public delegate = admin; // testnet address
    address public treasury = admin; // testnet address
    address public guardian = admin; // testnet address

    function setUp() public {}

    function run() public {
        // Let's do the same thing with `getCode`
        bytes memory args = abi.encode(name, symbol, endpoint, delegate, treasury, guardian);
        bytes memory bytecode = abi.encodePacked(vm.getCode("CdxUSD.sol:CdxUSD"), args);

        console2.logBytes(bytecode);
    }
}
