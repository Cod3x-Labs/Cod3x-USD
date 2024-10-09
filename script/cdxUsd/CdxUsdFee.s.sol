// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script, console2} from "forge-std/Script.sol";
import "forge-std/console.sol";
import "./Constants.sol";
import "contracts/tokens/CdxUSD.sol";

contract CdxUsdFee is Script, Constants {
    function setUp() public {}

    function run() public {
        vm.broadcast();
        CdxUSD(cdxUsdTestNet).setFee(0);
    }
}
