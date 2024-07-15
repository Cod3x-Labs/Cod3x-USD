// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {OFTExtended} from "./OFTExtended.sol";
import {ICdxUSD} from "./interfaces/ICdxUSD.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/**
 * @title CdxUSD Contract
 * @author Cod3x - Beirao
 * Reference: https://github.com/aave/gho-core/blob/main/src/contracts/gho/GhoToken.sol
 */
contract CdxUSD is ICdxUSD, OFTExtended {
    using EnumerableSet for EnumerableSet.AddressSet;

    mapping(address => Facilitator) internal facilitators;
    EnumerableSet.AddressSet internal facilitatorsList;

    constructor(
        string memory _name,
        string memory _symbol,
        address _lzEndpoint,
        address _delegate,
        address _treasury,
        address _guardian
    ) OFTExtended(_name, _symbol, _lzEndpoint, _delegate, _treasury, _guardian) {}

    /**
     * @notice Mints the requested amount of tokens to the account address.
     * @dev Only facilitators with enough bucket capacity available can mint.
     * @dev The bucket level is increased upon minting.
     * @param _account The address receiving the GHO tokens
     * @param _amount The amount to mint
     */
    function mint(address _account, uint256 _amount) external {
        if (_amount == 0) revert CdxUSD__INVALID_MINT_AMOUNT();
        Facilitator storage f = facilitators[msg.sender];

        uint256 currentBucketLevel_ = f.bucketLevel;
        uint256 newBucketLevel_ = currentBucketLevel_ + _amount;
        if (f.bucketCapacity < newBucketLevel_) {
            revert CdxUSD__FACILITATOR_BUCKET_CAPACITY_EXCEEDED();
        }
        f.bucketLevel = uint128(newBucketLevel_);

        _mint(_account, _amount);

        emit FacilitatorBucketLevelUpdated(msg.sender, currentBucketLevel_, newBucketLevel_);
    }

    /**
     * @notice Burns the requested amount of tokens from the account address.
     * @dev Only active facilitators (bucket level > 0) can burn.
     * @dev The bucket level is decreased upon burning.
     * @param _amount The amount to burn
     */
    function burn(uint256 _amount) external {
        if (_amount == 0) revert CdxUSD__INVALID_BURN_AMOUNT();

        Facilitator storage f = facilitators[msg.sender];
        uint256 currentBucketLevel_ = f.bucketLevel;
        uint256 newBucketLevel_ = currentBucketLevel_ - _amount;
        f.bucketLevel = uint128(newBucketLevel_);

        _burn(msg.sender, _amount);

        emit FacilitatorBucketLevelUpdated(msg.sender, currentBucketLevel_, newBucketLevel_);
    }

    /**
     * @notice Add the facilitator passed with the parameters to the facilitators list.
     * @dev Only accounts with `FACILITATOR_MANAGER_ROLE` role can call this function
     * @param _facilitatorAddress The address of the facilitator to add
     * @param _facilitatorLabel A human readable identifier for the facilitator
     * @param _bucketCapacity The upward limit of GHO can be minted by the facilitator
     */
    function addFacilitator(
        address _facilitatorAddress,
        string calldata _facilitatorLabel,
        uint128 _bucketCapacity
    ) external onlyOwner {
        Facilitator storage facilitator = facilitators[_facilitatorAddress];

        if (bytes(facilitator.label).length != 0) revert CdxUSD__FACILITATOR_ALREADY_EXISTS();
        if (bytes(_facilitatorLabel).length == 0) revert CdxUSD__INVALID_LABEL();

        facilitator.label = _facilitatorLabel;
        facilitator.bucketCapacity = _bucketCapacity;

        facilitatorsList.add(_facilitatorAddress);

        emit FacilitatorAdded(
            _facilitatorAddress, keccak256(abi.encodePacked(_facilitatorLabel)), _bucketCapacity
        );
    }

    /**
     * @notice Remove the facilitator from the facilitators list.
     * @dev Only accounts with `FACILITATOR_MANAGER_ROLE` role can call this function
     * @param _facilitatorAddress The address of the facilitator to remove
     */
    function removeFacilitator(address _facilitatorAddress) external onlyOwner {
        if (bytes(facilitators[_facilitatorAddress].label).length == 0) {
            revert CdxUSD__FACILITATOR_DOES_NOT_EXIST();
        }
        if (facilitators[_facilitatorAddress].bucketLevel != 0) {
            revert CdxUSD__FACILITATOR_BUCKET_LEVEL_NOT_ZERO();
        }

        delete facilitators[_facilitatorAddress];
        facilitatorsList.remove(_facilitatorAddress);

        emit FacilitatorRemoved(_facilitatorAddress);
    }

    /**
     * @notice Set the bucket capacity of the facilitator.
     * @dev Only accounts with `BUCKET_MANAGER_ROLE` role can call this function
     * @param _facilitator The address of the facilitator
     * @param _newCapacity The new capacity of the bucket
     */
    function setFacilitatorBucketCapacity(address _facilitator, uint128 _newCapacity)
        external
        onlyOwner
    {
        if (bytes(facilitators[_facilitator].label).length == 0) {
            revert CdxUSD__FACILITATOR_DOES_NOT_EXIST();
        }

        uint256 oldCapacity_ = facilitators[_facilitator].bucketCapacity;
        facilitators[_facilitator].bucketCapacity = _newCapacity;

        emit FacilitatorBucketCapacityUpdated(_facilitator, oldCapacity_, _newCapacity);
    }

    /**
     * @notice Returns the facilitator data
     * @param _facilitator The address of the facilitator
     * @return The facilitator configuration
     */
    function getFacilitator(address _facilitator) external view returns (Facilitator memory) {
        return facilitators[_facilitator];
    }

    /**
     * @notice Returns the bucket configuration of the facilitator
     * @param _facilitator The address of the facilitator
     * @return The capacity of the facilitator's bucket
     * @return The level of the facilitator's bucket
     */
    function getFacilitatorBucket(address _facilitator) external view returns (uint256, uint256) {
        return (facilitators[_facilitator].bucketCapacity, facilitators[_facilitator].bucketLevel);
    }

    /**
     * @notice Returns the list of the addresses of the active facilitator
     * @return The list of the facilitators addresses
     */
    function getFacilitatorsList() external view returns (address[] memory) {
        return facilitatorsList.values();
    }
}
