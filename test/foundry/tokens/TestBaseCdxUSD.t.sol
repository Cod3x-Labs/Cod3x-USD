// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

/// LayerZero
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

/// Main import
import "@openzeppelin/contracts/utils/Strings.sol";
import "contracts/tokens/CdxUSD.sol";
import "contracts/tokens/interfaces/ICdxUSD.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import "test/helpers/Events.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

import {TestCdxUSD} from "test/helpers/TestCdxUSD.sol";

contract TestBaseCdxUSD is TestCdxUSD {
    uint128 public initialBalance = 100 ether;

    function setUp() public virtual override {
        vm.deal(userA, 1000 ether);
        vm.deal(userB, 1000 ether);

        super.setUp();
        setUpEndpoints(2, LibraryType.UltraLightNode);

        cdxUSD = CdxUSD(
            _deployOApp(
                type(CdxUSD).creationCode,
                abi.encode("aOFT", "aOFT", address(endpoints[aEid]), owner, treasury, guardian)
            )
        );

        cdxUSD.addFacilitator(userA, "user a", initialBalance);
    }

    function testGetFacilitatorData() public {
        ICdxUSD.Facilitator memory data = cdxUSD.getFacilitator(userA);
        assertEq(data.label, "user a", "Unexpected facilitator label");
        assertEq(data.bucketCapacity, initialBalance, "Unexpected bucket capacity");
        assertEq(data.bucketLevel, 0, "Unexpected bucket level");
    }

    function testGetNonFacilitatorData() public {
        ICdxUSD.Facilitator memory data = cdxUSD.getFacilitator(userB);
        assertEq(data.label, "", "Unexpected facilitator label");
        assertEq(data.bucketCapacity, 0, "Unexpected bucket capacity");
        assertEq(data.bucketLevel, 0, "Unexpected bucket level");
    }

    function testGetFacilitatorBucket() public {
        (uint256 capacity, uint256 level) = cdxUSD.getFacilitatorBucket(userA);
        assertEq(capacity, initialBalance, "Unexpected bucket capacity");
        assertEq(level, 0, "Unexpected bucket level");
    }

    function testGetNonFacilitatorBucket() public {
        (uint256 capacity, uint256 level) = cdxUSD.getFacilitatorBucket(userB);
        assertEq(capacity, 0, "Unexpected bucket capacity");
        assertEq(level, 0, "Unexpected bucket level");
    }

    function testGetPopulatedFacilitatorsList() public {
        cdxUSD.addFacilitator(userB, "user b", initialBalance);

        address[] memory facilitatorList = cdxUSD.getFacilitatorsList();
        assertEq(facilitatorList.length, 2, "Unexpected number of facilitators");
        assertEq(facilitatorList[0], userA, "Unexpected address for mock facilitator 1");
        assertEq(facilitatorList[1], userB, "Unexpected address for mock facilitator 2");
    }

    function testAddFacilitator() public {
        vm.expectEmit(true, true, false, true, address(cdxUSD));
        emit FacilitatorAdded(userC, keccak256(abi.encodePacked("Alice")), initialBalance);
        cdxUSD.addFacilitator(userC, "Alice", initialBalance);
    }

    function testRevertAddExistingFacilitator() public {
        vm.expectRevert(ICdxUSD.CdxUSD__FACILITATOR_ALREADY_EXISTS.selector);
        cdxUSD.addFacilitator(userA, "Aave V3 Pool", initialBalance);
    }

    function testRevertAddFacilitatorNoLabel() public {
        vm.expectRevert(ICdxUSD.CdxUSD__INVALID_LABEL.selector);
        cdxUSD.addFacilitator(userB, "", initialBalance);
    }

    function testRevertAddFacilitatorNoRole() public {
        vm.prank(userA);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, userA));
        cdxUSD.addFacilitator(userA, "Alice", initialBalance);
    }

    function testRevertSetBucketCapacityNonFacilitator() public {
        vm.expectRevert(ICdxUSD.CdxUSD__FACILITATOR_DOES_NOT_EXIST.selector);

        cdxUSD.setFacilitatorBucketCapacity(userB, initialBalance);
    }

    function testSetNewBucketCapacity() public {
        vm.expectEmit(true, false, false, true, address(cdxUSD));
        emit FacilitatorBucketCapacityUpdated(userA, initialBalance, 0);
        cdxUSD.setFacilitatorBucketCapacity(userA, 0);
    }

    function testSetNewBucketCapacityAsManager() public {
        cdxUSD.transferOwnership(userB);
        vm.prank(userB);
        vm.expectEmit(true, false, false, true, address(cdxUSD));
        emit FacilitatorBucketCapacityUpdated(userA, initialBalance, 0);
        cdxUSD.setFacilitatorBucketCapacity(userA, 0);

        vm.prank(userA);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, userA));
        cdxUSD.setFacilitatorBucketCapacity(userA, 0);
    }

    function testRevertSetNewBucketCapacityNoRole() public {
        vm.prank(userB);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, userB));
        cdxUSD.setFacilitatorBucketCapacity(userA, 0);
    }

    function testRevertRemoveNonFacilitator() public {
        vm.expectRevert(ICdxUSD.CdxUSD__FACILITATOR_DOES_NOT_EXIST.selector);
        cdxUSD.removeFacilitator(userB);
    }

    function testRevertRemoveFacilitatorNonZeroBucket() public {
        vm.prank(userA);
        cdxUSD.mint(userA, 1);

        vm.expectRevert(ICdxUSD.CdxUSD__FACILITATOR_BUCKET_LEVEL_NOT_ZERO.selector);
        cdxUSD.removeFacilitator(userA);
    }

    function testRemoveFacilitator() public {
        vm.expectEmit(true, false, false, true, address(cdxUSD));
        emit FacilitatorRemoved(userA);
        cdxUSD.removeFacilitator(userA);
    }

    function testRevertRemoveFacilitatorNoRole() public {
        vm.prank(userA);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, userA));
        cdxUSD.removeFacilitator(userA);
    }

    function testRevertMintBadFacilitator() public {
        vm.prank(userB);
        vm.expectRevert(ICdxUSD.CdxUSD__FACILITATOR_BUCKET_CAPACITY_EXCEEDED.selector);
        cdxUSD.mint(userA, 1);
    }

    function testRevertMintExceedCapacity() public {
        vm.prank(userA);
        vm.expectRevert(ICdxUSD.CdxUSD__FACILITATOR_BUCKET_CAPACITY_EXCEEDED.selector);
        cdxUSD.mint(userA, initialBalance + 1);
    }

    function testMint() public {
        vm.prank(userA);
        vm.expectEmit(true, true, false, true, address(cdxUSD));
        emit Transfer(address(0), userB, initialBalance);
        vm.expectEmit(true, false, false, true, address(cdxUSD));
        emit FacilitatorBucketLevelUpdated(userA, 0, initialBalance);
        cdxUSD.mint(userB, initialBalance);
    }

    function testRevertZeroMint() public {
        vm.prank(userA);
        vm.expectRevert(ICdxUSD.CdxUSD__INVALID_MINT_AMOUNT.selector);
        cdxUSD.mint(userB, 0);
    }

    function testRevertZeroBurn() public {
        vm.prank(userA);
        vm.expectRevert(ICdxUSD.CdxUSD__INVALID_BURN_AMOUNT.selector);
        cdxUSD.burn(0);
    }

    function testRevertBurnMoreThanMinted() public {
        vm.prank(userA);
        vm.expectEmit(true, false, false, true, address(cdxUSD));
        emit FacilitatorBucketLevelUpdated(userA, 0, initialBalance);
        cdxUSD.mint(userA, initialBalance);

        vm.prank(userA);
        vm.expectRevert();
        cdxUSD.burn(initialBalance + 1);
    }

    function testRevertBurnOthersTokens() public {
        vm.prank(userA);
        vm.expectEmit(true, true, false, true, address(cdxUSD));
        emit Transfer(address(0), userB, initialBalance);
        vm.expectEmit(true, false, false, true, address(cdxUSD));
        emit FacilitatorBucketLevelUpdated(userA, 0, initialBalance);
        cdxUSD.mint(userB, initialBalance);

        vm.prank(userA);
        vm.expectRevert();
        cdxUSD.burn(initialBalance);
    }

    function testBurn() public {
        vm.prank(userA);
        vm.expectEmit(true, true, false, true, address(cdxUSD));
        emit Transfer(address(0), userA, initialBalance);
        vm.expectEmit(true, false, false, true, address(cdxUSD));
        emit FacilitatorBucketLevelUpdated(userA, 0, initialBalance);
        cdxUSD.mint(userA, initialBalance);

        // vm.prank(userA);
        // vm.expectEmit(true, false, false, true, address(cdxUSD));
        // emit FacilitatorBucketLevelUpdated(userA, initialBalance, initialBalance - 1000);
        // cdxUSD.burn(1000);
    }

    function testOffboardFacilitator() public {
        // Onboard facilitator
        vm.expectEmit(true, true, false, true, address(cdxUSD));
        emit FacilitatorAdded(userB, keccak256(abi.encodePacked("Alice")), initialBalance);
        cdxUSD.addFacilitator(userB, "Alice", initialBalance);

        // Facilitator mints half of its capacity
        vm.prank(userB);
        cdxUSD.mint(userB, initialBalance / 2);
        (uint256 bucketCapacity, uint256 bucketLevel) = cdxUSD.getFacilitatorBucket(userB);
        assertEq(bucketCapacity, initialBalance, "Unexpected bucket capacity of facilitator");
        assertEq(bucketLevel, initialBalance / 2, "Unexpected bucket level of facilitator");

        // Facilitator cannot be removed
        vm.expectRevert(ICdxUSD.CdxUSD__FACILITATOR_BUCKET_LEVEL_NOT_ZERO.selector);
        cdxUSD.removeFacilitator(userB);

        // Facilitator Bucket Capacity set to 0
        cdxUSD.setFacilitatorBucketCapacity(userB, 0);

        // Facilitator cannot mint more and is expected to burn remaining level
        vm.prank(userB);
        vm.expectRevert(ICdxUSD.CdxUSD__FACILITATOR_BUCKET_CAPACITY_EXCEEDED.selector);
        cdxUSD.mint(userB, 1);

        vm.prank(userB);
        cdxUSD.burn(bucketLevel);

        // Facilitator can be removed with 0 bucket level
        vm.expectEmit(true, false, false, true, address(cdxUSD));
        emit FacilitatorRemoved(address(userB));
        cdxUSD.removeFacilitator(address(userB));
    }

    function testDomainSeparator() public {
        bytes32 EIP712_DOMAIN = keccak256(
            "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
        );
        bytes memory EIP712_REVISION = bytes("1");
        bytes32 expected = keccak256(
            abi.encode(
                EIP712_DOMAIN,
                keccak256(bytes(cdxUSD.name())),
                keccak256(EIP712_REVISION),
                block.chainid,
                address(cdxUSD)
            )
        );
        bytes32 result = cdxUSD.DOMAIN_SEPARATOR();
        assertEq(result, expected, "Unexpected domain separator");
    }

    function testDomainSeparatorNewChain() public {
        vm.chainId(31338);
        bytes32 EIP712_DOMAIN = keccak256(
            "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
        );
        bytes memory EIP712_REVISION = bytes("1");
        bytes32 expected = keccak256(
            abi.encode(
                EIP712_DOMAIN,
                keccak256(bytes(cdxUSD.name())),
                keccak256(EIP712_REVISION),
                block.chainid,
                address(cdxUSD)
            )
        );
        bytes32 result = cdxUSD.DOMAIN_SEPARATOR();
        assertEq(result, expected, "Unexpected domain separator");
    }

    function testPermitAndVerifyNonce() public {
        (address david, uint256 davidKey) = makeAddrAndKey("david");
        vm.prank(userA);
        cdxUSD.mint(david, 1e18);
        bytes32 PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;
        bytes32 innerHash = keccak256(abi.encode(PERMIT_TYPEHASH, david, userC, 1e18, 0, 1 hours));
        bytes32 outerHash =
            keccak256(abi.encodePacked("\x19\x01", cdxUSD.DOMAIN_SEPARATOR(), innerHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(davidKey, outerHash);
        cdxUSD.permit(david, userC, 1e18, 1 hours, v, r, s);

        assertEq(cdxUSD.allowance(david, userC), 1e18, "Unexpected allowance");
        assertEq(cdxUSD.nonces(david), 1, "Unexpected nonce");
    }

    function testRevertPermitInvalidSignature() public {
        (address david, uint256 davidKey) = makeAddrAndKey("david");
        bytes32 PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;
        bytes32 innerHash = keccak256(abi.encode(PERMIT_TYPEHASH, userB, userC, 1e18, 0, 1 hours));
        bytes32 outerHash =
            keccak256(abi.encodePacked("\x19\x01", cdxUSD.DOMAIN_SEPARATOR(), innerHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(davidKey, outerHash);

        vm.expectRevert(
            abi.encodeWithSelector(ERC20Permit.ERC2612InvalidSigner.selector, david, userB)
        );
        cdxUSD.permit(userB, userC, 1e18, 1 hours, v, r, s);
    }

    function testRevertPermitInvalidDeadline() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC20Permit.ERC2612ExpiredSignature.selector, block.timestamp - 1
            )
        );
        cdxUSD.permit(userB, userC, 1e18, block.timestamp - 1, 0, 0, 0);
    }
}
