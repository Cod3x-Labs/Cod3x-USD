// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script, console2} from "forge-std/Script.sol";
import "forge-std/console2.sol";
import "../DeploymentConstants.s.sol";
import "contracts/tokens/CdxUSD.sol";

contract CdxUsdAddFacilitator is Script, DeploymentConstants {
    function setUp() public {}

    function run() public {
        vm.broadcast();
        CdxUSD(cdxUsd).addFacilitator(admin, "admin", 100_000e18);
    }
}
