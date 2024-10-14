// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script, console2} from "forge-std/Script.sol";
import "forge-std/console.sol";
import "../Constants.sol";
import "contracts/tokens/CdxUSD.sol";

// OApp imports
import {
    IOFT,
    SendParam,
    OFTReceipt
} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";
import {OptionsBuilder} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";
import {
    MessagingFee, MessagingReceipt
} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFTCore.sol";

contract CdxUsdBridge is Script, Constants {
    using OptionsBuilder for bytes;

    function setUp() public {}

    function run() public {
        // Fetching environment variables
        address toAddress = admin;
        uint256 _tokensToSend = 1000e18;

        // Start broadcasting with the private key
        vm.startBroadcast();

        CdxUSD sourceOFT = CdxUSD(cdxUsd);

        bytes memory _extraOptions =
            OptionsBuilder.newOptions().addExecutorLzReceiveOption(65000, 0);
        SendParam memory sendParam = SendParam(
            40267,
            addressToBytes32(toAddress),
            _tokensToSend,
            _tokensToSend * 9 / 10,
            _extraOptions,
            "",
            ""
        );

        MessagingFee memory fee = sourceOFT.quoteSend(sendParam, false);

        console.log("Fee amount: ", fee.nativeFee);

        sourceOFT.send{value: fee.nativeFee}(sendParam, fee, msg.sender);

        vm.stopBroadcast();
    }

    function addressToBytes32(address _addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(_addr)));
    }
}
