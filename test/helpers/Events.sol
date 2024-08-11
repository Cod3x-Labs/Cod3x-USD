// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface Events {
    // core token events
    event Mint(
        address indexed caller,
        address indexed onBehalfOf,
        uint256 value,
        uint256 balanceIncrease,
        uint256 index
    );
    event Burn(
        address indexed from,
        address indexed target,
        uint256 value,
        uint256 balanceIncrease,
        uint256 index
    );
    event Transfer(address indexed from, address indexed to, uint256 value);

    // flashmint-related events
    event FlashMint(
        address indexed receiver,
        address indexed initiator,
        address asset,
        uint256 indexed amount,
        uint256 fee
    );
    event FeeUpdated(uint256 oldFee, uint256 newFee);

    // facilitator-related events
    event FacilitatorAdded(
        address indexed facilitatorAddress, bytes32 indexed label, uint256 bucketCapacity
    );
    event FacilitatorRemoved(address indexed facilitatorAddress);
    event FacilitatorBucketCapacityUpdated(
        address indexed facilitatorAddress, uint256 oldCapacity, uint256 newCapacity
    );
    event FacilitatorBucketLevelUpdated(
        address indexed facilitatorAddress, uint256 oldLevel, uint256 newLevel
    );

    // Ownable
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    // Upgrades
    event Upgraded(address indexed implementation);
}
