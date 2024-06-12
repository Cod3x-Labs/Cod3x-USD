// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

// Mock imports
import {OFTMock} from "../../helpers/mocks/OFTMock.sol";
import {ERC20Mock} from "../../helpers/mocks/ERC20Mock.sol";
import {OFTComposerMock} from "../../helpers/mocks/OFTComposerMock.sol";
import {IOFTExtended} from "contracts/tokens/interfaces/IOFTExtended.sol";

// OApp imports
import {
    IOAppOptionsType3,
    EnforcedOptionParam
} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OAppOptionsType3.sol";
import {OptionsBuilder} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";

// OFT imports
import {
    IOFT,
    SendParam,
    OFTReceipt
} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/interfaces/IOFT.sol";
import {
    MessagingFee, MessagingReceipt
} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFTCore.sol";
import {OFTMsgCodec} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/libs/OFTMsgCodec.sol";
import {OFTComposeMsgCodec} from
    "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/libs/OFTComposeMsgCodec.sol";

// DevTools imports
import {TestCdxUSD} from "test/helpers/TestCdxUSD.sol";

contract TestLayerZeroCdxUSD is TestCdxUSD {
    using OptionsBuilder for bytes;

    OFTMock aOFT;
    OFTMock bOFT;

    uint256 public initialBalance = 100 ether;

    function setUp() public virtual override {
        super.setUp();
        setUpEndpoints(2, LibraryType.UltraLightNode);

        aOFT = OFTMock(
            _deployOApp(
                type(OFTMock).creationCode,
                abi.encode("aOFT", "aOFT", address(endpoints[aEid]), owner, treasury, guardian)
            )
        );

        bOFT = OFTMock(
            _deployOApp(
                type(OFTMock).creationCode,
                abi.encode("bOFT", "bOFT", address(endpoints[bEid]), owner, treasury, guardian)
            )
        );

        // config and wire the ofts
        address[] memory ofts = new address[](2);
        ofts[0] = address(aOFT);
        ofts[1] = address(bOFT);
        this.wireOApps(ofts);

        aOFT.setBridgeConfig(bEid, type(int112).min, type(uint104).max, 0);
        bOFT.setBridgeConfig(aEid, type(int112).min, type(uint104).max, 0);

        // mint tokens
        aOFT.mockMint(userA, initialBalance);
        bOFT.mockMint(userB, initialBalance);
    }

    function testConstructor() public {
        assertEq(aOFT.owner(), address(this));
        assertEq(bOFT.owner(), address(this));

        assertEq(aOFT.treasury(), treasury);
        assertEq(bOFT.treasury(), treasury);

        assertEq(aOFT.guardian(), guardian);
        assertEq(bOFT.guardian(), guardian);

        assertEq(aOFT.balanceOf(userA), initialBalance);
        assertEq(bOFT.balanceOf(userB), initialBalance);

        assertEq(aOFT.token(), address(aOFT));
        assertEq(bOFT.token(), address(bOFT));
    }

    function testLzPause() public {
        aOFT.toggleBridgePause();

        uint256 tokensToSend = 1 ether;
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory sendParam =
            SendParam(bEid, addressToBytes32(userB), tokensToSend, tokensToSend, options, "", "");
        MessagingFee memory fee = aOFT.quoteSend(sendParam, false);

        assertEq(aOFT.balanceOf(userA), initialBalance);
        assertEq(bOFT.balanceOf(userB), initialBalance);

        vm.prank(userA);
        vm.expectRevert(IOFTExtended.OFTExtended__BRIDGING_PAUSED.selector);
        aOFT.send{value: fee.nativeFee}(sendParam, fee, payable(address(this)));

        assertEq(aOFT.balanceOf(userA), initialBalance);
        assertEq(bOFT.balanceOf(userB), initialBalance);

        vm.prank(guardian);
        aOFT.toggleBridgePause();

        testSendOftAToB();
    }

    function testSendOftAToB() public {
        uint256 tokensToSend = 1 ether;
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory sendParam =
            SendParam(bEid, addressToBytes32(userB), tokensToSend, tokensToSend, options, "", "");
        MessagingFee memory fee = aOFT.quoteSend(sendParam, false);

        assertEq(aOFT.balanceOf(userA), initialBalance);
        assertEq(bOFT.balanceOf(userB), initialBalance);

        vm.prank(userA);
        aOFT.send{value: fee.nativeFee}(sendParam, fee, payable(address(this)));
        verifyPackets(bEid, addressToBytes32(address(bOFT)));

        assertEq(aOFT.balanceOf(userA), initialBalance - tokensToSend);
        assertEq(bOFT.balanceOf(userB), initialBalance + tokensToSend);
    }

    function testSendOftBToA() public {
        uint256 tokensToSend = 1 ether;
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory sendParam =
            SendParam(aEid, addressToBytes32(userA), tokensToSend, tokensToSend, options, "", "");
        MessagingFee memory fee = bOFT.quoteSend(sendParam, false);

        assertEq(aOFT.balanceOf(userA), initialBalance);
        assertEq(bOFT.balanceOf(userB), initialBalance);

        vm.prank(userB);
        bOFT.send{value: fee.nativeFee}(sendParam, fee, payable(address(this)));
        verifyPackets(aEid, addressToBytes32(address(aOFT)));

        assertEq(bOFT.balanceOf(userB), initialBalance - tokensToSend);
        assertEq(aOFT.balanceOf(userA), initialBalance + tokensToSend);
    }

    function testSendOftComposeMsg() public {
        uint256 tokensToSend = 1 ether;

        OFTComposerMock composer = new OFTComposerMock();

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0)
            .addExecutorLzComposeOption(0, 500000, 0);
        bytes memory composeMsg = hex"1234";
        SendParam memory sendParam = SendParam(
            bEid,
            addressToBytes32(address(composer)),
            tokensToSend,
            tokensToSend,
            options,
            composeMsg,
            ""
        );
        MessagingFee memory fee = aOFT.quoteSend(sendParam, false);

        assertEq(aOFT.balanceOf(userA), initialBalance);
        assertEq(bOFT.balanceOf(address(composer)), 0);

        vm.prank(userA);
        (MessagingReceipt memory msgReceipt, OFTReceipt memory oftReceipt) =
            aOFT.send{value: fee.nativeFee}(sendParam, fee, payable(address(this)));
        verifyPackets(bEid, addressToBytes32(address(bOFT)));

        // lzCompose params
        uint32 dstEid_ = bEid;
        address from_ = address(bOFT);
        bytes memory options_ = options;
        bytes32 guid_ = msgReceipt.guid;
        address to_ = address(composer);
        bytes memory composerMsg_ = OFTComposeMsgCodec.encode(
            msgReceipt.nonce,
            aEid,
            oftReceipt.amountReceivedLD,
            abi.encodePacked(addressToBytes32(userA), composeMsg)
        );
        this.lzCompose(dstEid_, from_, options_, guid_, to_, composerMsg_);

        assertEq(aOFT.balanceOf(userA), initialBalance - tokensToSend);
        assertEq(bOFT.balanceOf(address(composer)), tokensToSend);

        assertEq(composer.from(), from_);
        assertEq(composer.guid(), guid_);
        assertEq(composer.message(), composerMsg_);
        assertEq(composer.executor(), address(this));
        assertEq(composer.extraData(), composerMsg_); // default to setting the extraData to the message as well to test
    }

    function testOftComposeCodec() public {
        uint64 nonce = 1;
        uint32 srcEid = 2;
        uint256 amountCreditLD = 3;
        bytes memory composeMsg = hex"1234";

        bytes memory message = OFTComposeMsgCodec.encode(
            nonce,
            srcEid,
            amountCreditLD,
            abi.encodePacked(addressToBytes32(msg.sender), composeMsg)
        );
        (
            uint64 nonce_,
            uint32 srcEid_,
            uint256 amountCreditLD_,
            bytes32 composeFrom_,
            bytes memory composeMsg_
        ) = this.decodeOFTComposeMsgCodec(message);

        assertEq(nonce_, nonce);
        assertEq(srcEid_, srcEid);
        assertEq(amountCreditLD_, amountCreditLD);
        assertEq(composeFrom_, addressToBytes32(msg.sender));
        assertEq(composeMsg_, composeMsg);
    }

    function decodeOFTComposeMsgCodec(bytes calldata message)
        public
        pure
        returns (
            uint64 nonce,
            uint32 srcEid,
            uint256 amountCreditLD,
            bytes32 composeFrom,
            bytes memory composeMsg
        )
    {
        nonce = OFTComposeMsgCodec.nonce(message);
        srcEid = OFTComposeMsgCodec.srcEid(message);
        amountCreditLD = OFTComposeMsgCodec.amountLD(message);
        composeFrom = OFTComposeMsgCodec.composeFrom(message);
        composeMsg = OFTComposeMsgCodec.composeMsg(message);
    }

    function testDebitSlippageRemoveDust() public {
        uint256 amountToSendLD = 1.23456789 ether;
        uint256 minAmountToCreditLD = 1.23456789 ether;
        uint32 dstEid = aEid;

        // remove the dust form the shared decimal conversion
        assertEq(aOFT.removeDust(amountToSendLD), 1.234567 ether);

        vm.expectRevert(
            abi.encodeWithSelector(
                IOFT.SlippageExceeded.selector, aOFT.removeDust(amountToSendLD), minAmountToCreditLD
            )
        );
        aOFT.debit(amountToSendLD, minAmountToCreditLD, dstEid);
    }

    function testDebitSlippageMinAmountToCreditLD() public {
        uint256 amountToSendLD = 1 ether;
        uint256 minAmountToCreditLD = 1.00000001 ether;
        uint32 dstEid = aEid;

        vm.expectRevert(
            abi.encodeWithSelector(
                IOFT.SlippageExceeded.selector, amountToSendLD, minAmountToCreditLD
            )
        );
        aOFT.debit(amountToSendLD, minAmountToCreditLD, dstEid);
    }

    function testToLD() public {
        uint64 amountSD = 1000;
        assertEq(amountSD * aOFT.decimalConversionRate(), aOFT.toLD(uint64(amountSD)));
    }

    function testToSD() public {
        uint256 amountLD = 1000000;
        assertEq(amountLD / aOFT.decimalConversionRate(), aOFT.toSD(amountLD));
    }

    function testOftDebit() public {
        aOFT.setBridgeConfig(aEid, type(int112).min, type(uint104).max, 0);

        uint256 amountToSendLD = 1 ether;
        uint256 minAmountToCreditLD = 1 ether;
        uint32 dstEid = aEid;

        assertEq(aOFT.balanceOf(userA), initialBalance);
        assertEq(aOFT.balanceOf(address(this)), 0);

        vm.prank(userA);
        (uint256 amountDebitedLD, uint256 amountToCreditLD) =
            aOFT.debit(amountToSendLD, minAmountToCreditLD, dstEid);

        assertEq(amountDebitedLD, amountToSendLD);
        assertEq(amountToCreditLD, amountToSendLD);

        assertEq(aOFT.balanceOf(userA), initialBalance - amountToSendLD);
        assertEq(aOFT.balanceOf(address(this)), 0);
    }

    function testOftCredit() public {
        uint256 amountToCreditLD = 1 ether;
        uint32 srcEid = aEid;

        assertEq(aOFT.balanceOf(userA), initialBalance);
        assertEq(aOFT.balanceOf(address(this)), 0);

        vm.prank(userA);
        uint256 amountReceived = aOFT.credit(userA, amountToCreditLD, srcEid);

        assertEq(aOFT.balanceOf(userA), initialBalance + amountReceived);
        assertEq(aOFT.balanceOf(address(this)), 0);
    }

    function decodeOFTMsgCodec(bytes calldata message)
        public
        pure
        returns (bool isComposed, bytes32 sendTo, uint64 amountSD, bytes memory composeMsg)
    {
        isComposed = OFTMsgCodec.isComposed(message);
        sendTo = OFTMsgCodec.sendTo(message);
        amountSD = OFTMsgCodec.amountSD(message);
        composeMsg = OFTMsgCodec.composeMsg(message);
    }

    function testOftBuildMsg() public {
        uint32 dstEid = bEid;
        bytes32 to = addressToBytes32(userA);
        uint256 amountToSendLD = 1.23456789 ether;
        uint256 minAmountToCreditLD = aOFT.removeDust(amountToSendLD);

        // params for buildMsgAndOptions
        bytes memory extraOptions =
            OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        bytes memory composeMsg = hex"1234";
        SendParam memory sendParam =
            SendParam(dstEid, to, amountToSendLD, minAmountToCreditLD, extraOptions, composeMsg, "");
        uint256 amountToCreditLD = minAmountToCreditLD;

        (bytes memory message,) = aOFT.buildMsgAndOptions(sendParam, amountToCreditLD);

        (bool isComposed_, bytes32 sendTo_, uint64 amountSD_, bytes memory composeMsg_) =
            this.decodeOFTMsgCodec(message);

        assertEq(isComposed_, true);
        assertEq(sendTo_, to);
        assertEq(amountSD_, aOFT.toSD(amountToCreditLD));
        bytes memory expectedComposeMsg =
            abi.encodePacked(addressToBytes32(address(this)), composeMsg);
        assertEq(composeMsg_, expectedComposeMsg);
    }

    function testOftBuildMsgNoComposeMsg() public {
        uint32 dstEid = bEid;
        bytes32 to = addressToBytes32(userA);
        uint256 amountToSendLD = 1.23456789 ether;
        uint256 minAmountToCreditLD = aOFT.removeDust(amountToSendLD);

        // params for buildMsgAndOptions
        bytes memory extraOptions =
            OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        bytes memory composeMsg = "";
        SendParam memory sendParam =
            SendParam(dstEid, to, amountToSendLD, minAmountToCreditLD, extraOptions, composeMsg, "");
        uint256 amountToCreditLD = minAmountToCreditLD;

        (bytes memory message,) = aOFT.buildMsgAndOptions(sendParam, amountToCreditLD);

        (bool isComposed_, bytes32 sendTo_, uint64 amountSD_, bytes memory composeMsg_) =
            this.decodeOFTMsgCodec(message);

        assertEq(isComposed_, false);
        assertEq(sendTo_, to);
        assertEq(amountSD_, aOFT.toSD(amountToCreditLD));
        assertEq(composeMsg_, "");
    }

    function testSetEnforcedOptions() public {
        uint32 eid = 1;

        bytes memory optionsTypeOne =
            OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        bytes memory optionsTypeTwo =
            OptionsBuilder.newOptions().addExecutorLzReceiveOption(250000, 0);

        EnforcedOptionParam[] memory enforcedOptions = new EnforcedOptionParam[](2);
        enforcedOptions[0] = EnforcedOptionParam(eid, 1, optionsTypeOne);
        enforcedOptions[1] = EnforcedOptionParam(eid, 2, optionsTypeTwo);

        aOFT.setEnforcedOptions(enforcedOptions);

        assertEq(aOFT.enforcedOptions(eid, 1), optionsTypeOne);
        assertEq(aOFT.enforcedOptions(eid, 2), optionsTypeTwo);
    }

    function testAssertOptionsType3Revert() public {
        uint32 eid = 1;
        EnforcedOptionParam[] memory enforcedOptions = new EnforcedOptionParam[](1);

        enforcedOptions[0] = EnforcedOptionParam(eid, 1, hex"0004"); // not type 3
        vm.expectRevert(
            abi.encodeWithSelector(IOAppOptionsType3.InvalidOptions.selector, hex"0004")
        );
        aOFT.setEnforcedOptions(enforcedOptions);

        enforcedOptions[0] = EnforcedOptionParam(eid, 1, hex"0002"); // not type 3
        vm.expectRevert(
            abi.encodeWithSelector(IOAppOptionsType3.InvalidOptions.selector, hex"0002")
        );
        aOFT.setEnforcedOptions(enforcedOptions);

        enforcedOptions[0] = EnforcedOptionParam(eid, 1, hex"0001"); // not type 3
        vm.expectRevert(
            abi.encodeWithSelector(IOAppOptionsType3.InvalidOptions.selector, hex"0001")
        );
        aOFT.setEnforcedOptions(enforcedOptions);

        enforcedOptions[0] = EnforcedOptionParam(eid, 1, hex"0003"); // IS type 3
        aOFT.setEnforcedOptions(enforcedOptions); // doesnt revert cus option type 3
    }

    function testCombineOptions() public {
        uint32 eid = 1;
        uint16 msgType = 1;

        bytes memory enforcedOptions =
            OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        EnforcedOptionParam[] memory enforcedOptionsArray = new EnforcedOptionParam[](1);
        enforcedOptionsArray[0] = EnforcedOptionParam(eid, msgType, enforcedOptions);
        aOFT.setEnforcedOptions(enforcedOptionsArray);

        bytes memory extraOptions = OptionsBuilder.newOptions().addExecutorNativeDropOption(
            1.2345 ether, addressToBytes32(userA)
        );

        bytes memory expectedOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(
            200000, 0
        ).addExecutorNativeDropOption(1.2345 ether, addressToBytes32(userA));

        bytes memory combinedOptions = aOFT.combineOptions(eid, msgType, extraOptions);
        assertEq(combinedOptions, expectedOptions);
    }

    function testCombineOptionsNoExtraOptions() public {
        uint32 eid = 1;
        uint16 msgType = 1;

        bytes memory enforcedOptions =
            OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        EnforcedOptionParam[] memory enforcedOptionsArray = new EnforcedOptionParam[](1);
        enforcedOptionsArray[0] = EnforcedOptionParam(eid, msgType, enforcedOptions);
        aOFT.setEnforcedOptions(enforcedOptionsArray);

        bytes memory expectedOptions =
            OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);

        bytes memory combinedOptions = aOFT.combineOptions(eid, msgType, "");
        assertEq(combinedOptions, expectedOptions);
    }

    function testCombineOptionsNoEnforcedOptions() public {
        uint32 eid = 1;
        uint16 msgType = 1;

        bytes memory extraOptions = OptionsBuilder.newOptions().addExecutorNativeDropOption(
            1.2345 ether, addressToBytes32(userA)
        );

        bytes memory expectedOptions = OptionsBuilder.newOptions().addExecutorNativeDropOption(
            1.2345 ether, addressToBytes32(userA)
        );

        bytes memory combinedOptions = aOFT.combineOptions(eid, msgType, extraOptions);
        assertEq(combinedOptions, expectedOptions);
    }

    function testLimitBridgeRate(uint256 _seedLimit, uint256 _seedAmountToSend) public {
        int112 _limit = -int112(uint112(bound(_seedLimit, 0, initialBalance * 2)));
        uint256 _amountToSend = _removeDust(bound(_seedAmountToSend, 0, initialBalance));

        bool isLimitTrigger = _amountToSend > uint256(-int256(_limit));

        aOFT.setBridgeConfig(bEid, _limit, type(uint104).max, 0);
        bOFT.setBridgeConfig(aEid, _limit, type(uint104).max, 0);

        if (isLimitTrigger) {
            bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
            SendParam memory sendParam =
                SendParam(bEid, addressToBytes32(userB), _amountToSend, 0, options, "", "");
            MessagingFee memory fee = aOFT.quoteSend(sendParam, false);

            assertEq(aOFT.balanceOf(userA), initialBalance);
            assertEq(bOFT.balanceOf(userB), initialBalance);

            vm.prank(userA);
            vm.expectRevert(
                abi.encodeWithSelector(IOFTExtended.OFTExtended__BRIDGING_LIMIT_REACHED.selector, 2)
            );
            aOFT.send{value: fee.nativeFee}(sendParam, fee, payable(address(this)));

            assertEq(aOFT.balanceOf(userA), initialBalance);
            assertEq(bOFT.balanceOf(userB), initialBalance);
        } else {
            bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
            SendParam memory sendParam =
                SendParam(bEid, addressToBytes32(userB), _amountToSend, 0, options, "", "");
            MessagingFee memory fee = aOFT.quoteSend(sendParam, false);

            assertEq(aOFT.balanceOf(userA), initialBalance);
            assertEq(bOFT.balanceOf(userB), initialBalance);

            vm.prank(userA);
            aOFT.send{value: fee.nativeFee}(sendParam, fee, payable(address(this)));
            verifyPackets(bEid, addressToBytes32(address(bOFT)));

            assertEq(aOFT.balanceOf(userA), initialBalance - _amountToSend);
            assertEq(bOFT.balanceOf(userB), initialBalance + _amountToSend);

            int112 balanceA = aOFT.getBridgeUtilization(bEid).balance;
            assertEq(abs(int256(balanceA)), _amountToSend);

            int112 balanceB = bOFT.getBridgeUtilization(aEid).balance;
            assertEq(abs(int256(balanceB)), _amountToSend);

            // 2nb send
            uint256 initialBalanceA = aOFT.balanceOf(userA);
            uint256 initialBalanceB = bOFT.balanceOf(userB);

            options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
            sendParam = SendParam(
                aEid, addressToBytes32(userA), _amountToSend, _amountToSend, options, "", ""
            );
            fee = bOFT.quoteSend(sendParam, false);

            vm.prank(userB);
            bOFT.send{value: fee.nativeFee}(sendParam, fee, payable(address(this)));
            verifyPackets(aEid, addressToBytes32(address(aOFT)));

            assertEq(bOFT.balanceOf(userB), initialBalanceB - _amountToSend);
            assertEq(aOFT.balanceOf(userA), initialBalanceA + _amountToSend);

            balanceA = aOFT.getBridgeUtilization(bEid).balance;
            assertEq(_removeDust(abs(int256(balanceA))), 0);

            balanceB = bOFT.getBridgeUtilization(aEid).balance;
            assertEq(_removeDust(abs(int256(balanceB))), 0);
        }
    }

    function testBridgingFees(uint256 _seedLimit, uint256 _seedAmountToSend) public {
        uint16 feeT = uint16(bound(_seedLimit, 0, 1000));
        uint256 tokensToSend = _removeDust(bound(_seedAmountToSend, 0, initialBalance));

        aOFT.setBridgeConfig(bEid, type(int112).min, type(uint104).max, feeT);
        bOFT.setBridgeConfig(aEid, type(int112).min, type(uint104).max, feeT);

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
        SendParam memory sendParam =
            SendParam(bEid, addressToBytes32(userB), tokensToSend, 0, options, "", "");
        MessagingFee memory fee = aOFT.quoteSend(sendParam, false);

        assertEq(aOFT.balanceOf(userA), initialBalance);
        assertEq(bOFT.balanceOf(userB), initialBalance);

        vm.prank(userA);
        aOFT.send{value: fee.nativeFee}(sendParam, fee, payable(address(this)));
        verifyPackets(bEid, addressToBytes32(address(bOFT)));

        uint256 tokensToSendWithFee = _removeDust(tokensToSend - (tokensToSend * feeT / 10000));
        assertEq(aOFT.balanceOf(treasury), tokensToSend - tokensToSendWithFee);
        assertEq(aOFT.balanceOf(userA), initialBalance - tokensToSend);
        assertEq(bOFT.balanceOf(userB), _removeDust(initialBalance + tokensToSendWithFee));
    }

    function testHourlyBridgingLimit(uint256 _seedHourlyLimit, uint256 _seedAmountToSend) public {
        uint104 _hourlyLimit = uint104(bound(_seedHourlyLimit, 0, initialBalance));
        uint256 _amountToSend = _removeDust(bound(_seedAmountToSend, 1e15, initialBalance / 2));

        bool isLimitTrigger = _amountToSend > uint256(_hourlyLimit);

        aOFT.setBridgeConfig(bEid, type(int112).min, _hourlyLimit, 0);
        bOFT.setBridgeConfig(aEid, type(int112).min, _hourlyLimit, 0);

        if (isLimitTrigger) {
            bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
            SendParam memory sendParam =
                SendParam(bEid, addressToBytes32(userB), _amountToSend, 0, options, "", "");
            MessagingFee memory fee = aOFT.quoteSend(sendParam, false);

            assertEq(aOFT.balanceOf(userA), initialBalance);
            assertEq(bOFT.balanceOf(userB), initialBalance);

            vm.prank(userA);
            vm.expectRevert(
                abi.encodeWithSelector(
                    IOFTExtended.OFTExtended__BRIDGING_HOURLY_LIMIT_REACHED.selector, 2
                )
            );
            aOFT.send{value: fee.nativeFee}(sendParam, fee, payable(address(this)));

            assertEq(aOFT.balanceOf(userA), initialBalance);
            assertEq(bOFT.balanceOf(userB), initialBalance);
        } else {
            aOFT.setBridgeConfig(bEid, type(int112).min, uint104(_amountToSend), 0);
            bOFT.setBridgeConfig(aEid, type(int112).min, uint104(_amountToSend), 0);

            bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
            SendParam memory sendParam =
                SendParam(bEid, addressToBytes32(userB), _amountToSend, 0, options, "", "");
            MessagingFee memory fee = aOFT.quoteSend(sendParam, false);

            assertEq(aOFT.balanceOf(userA), initialBalance);
            assertEq(bOFT.balanceOf(userB), initialBalance);

            vm.prank(userA);
            aOFT.send{value: fee.nativeFee}(sendParam, fee, payable(address(this)));
            verifyPackets(bEid, addressToBytes32(address(bOFT)));

            assertEq(aOFT.balanceOf(userA), initialBalance - _amountToSend);
            assertEq(bOFT.balanceOf(userB), initialBalance + _amountToSend);

            uint104 shluA = aOFT.getBridgeUtilization(bEid).slidingHourlyLimitUtilization;
            assertEq(shluA, _amountToSend);

            uint104 shluB = bOFT.getBridgeUtilization(aEid).slidingHourlyLimitUtilization;
            assertEq(shluB, 0);
            skip(30 minutes);

            // 2nb send
            sendParam =
                SendParam(bEid, addressToBytes32(userB), _amountToSend / 4, 0, options, "", "");
            fee = aOFT.quoteSend(sendParam, false);

            vm.prank(userA);
            aOFT.send{value: fee.nativeFee}(sendParam, fee, payable(address(this)));

            shluA = aOFT.getBridgeUtilization(bEid).slidingHourlyLimitUtilization;
            assertApproxEqRel(shluA, _amountToSend / 2 + _amountToSend / 4, 1e18 / 1000); // %0,1
        }
    }

    // ------------------- Helpers -------------------

    function _removeDust(uint256 _amountLD) internal pure returns (uint256 amountLD) {
        return (_amountLD / 1e12) * 1e12; // 18 - 6 = 12
    }

    function abs(int256 x) public pure returns (uint256) {
        return x < 0 ? uint256(-x) : uint256(x);
    }
}
