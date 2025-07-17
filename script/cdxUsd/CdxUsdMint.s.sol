// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script, console2} from "forge-std/Script.sol";
import "forge-std/console2.sol";
import "../DeploymentConstants.s.sol";
import "contracts/tokens/CdxUSD.sol";

contract CdxUsdMint is Script, DeploymentConstants {
    function setUp() public {}

    function run() public {
        vm.broadcast();
        CdxUSD(cdxUsd).mint(admin, 10_000e18);
    }
}
