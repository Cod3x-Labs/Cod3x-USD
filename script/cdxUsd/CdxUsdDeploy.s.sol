// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script, console2} from "forge-std/Script.sol";
import "forge-std/console.sol";
import "lib/createx/src/CreateX.sol";
import "./Constants.sol";
import "contracts/tokens/CdxUSD.sol";

contract CdxUsdDeploy is Script, Constants {
    string public name = "Cod3x USD";
    string public symbol = "cdxUSD";
    address public delegate = admin; // testnet address
    address public treasury = admin; // testnet address
    address public guardian = admin; // testnet address

    function setUp() public {}

    function run() public {
        bytes memory args = abi.encode(name, symbol, endpoint, delegate, treasury, guardian);
        bytes memory cachedInitCode = abi.encodePacked(type(CdxUSD).creationCode, args);

        vm.broadcast();
        address l = createx.deployCreate3{value: 0}(
            bytes32(0x3d0c000adf317206fa4a3201a8f8c926ef394fad0047c74b092069a800a5ed54),
            cachedInitCode
        );

        console.log("Chain id: ", block.chainid);
        console.log("CdxUSD address: ", l);
    }
}
