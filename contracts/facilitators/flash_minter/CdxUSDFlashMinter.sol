// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {PercentageMath} from "lib/Cod3x-Lend/contracts/protocol/libraries/math/PercentageMath.sol";
import {IERC3156FlashBorrower} from "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";
import {IERC3156FlashLender} from "@openzeppelin/contracts/interfaces/IERC3156FlashLender.sol";
import {ICdxUSD} from "contracts/interfaces/ICdxUSD.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ICdxUSDFacilitators} from "contracts/interfaces/ICdxUSDFacilitators.sol";

/**
 * @title CdxUSDFlashMinter
 * @author Cod3x - Beirao
 * @notice Contract that enables FlashMinting of cdxUSD.
 * @dev Based heavily on the EIP3156 reference implementation.
 * Based on: https://github.com/aave/gho-core/blob/main/src/contracts/facilitators/flashMinter/GhoFlashMinter.sol
 */
contract CdxUSDFlashMinter is ICdxUSDFacilitators, IERC3156FlashLender, Ownable {
    using PercentageMath for uint256;

    bytes32 public constant CALLBACK_SUCCESS = keccak256("ERC3156FlashBorrower.onFlashLoan");

    uint256 public constant MAX_FEE = 1e4;

    ICdxUSD public immutable cdxUSD;

    // The flashmint fee, expressed in bps (a value of 10000 results in 100.00%)
    uint256 private fee;

    // The cdxUSD treasury, the recipient of fee distributions
    address private cdxUsdTreasury;

    /// Errors
    error CdxUSDFlashMinter__FEE_OUT_OF_RANGE();
    error CdxUSDFlashMinter__UNSUPPORTED_ASSET();
    error CdxUSDFlashMinter__CALLBACK_FAILED();

    /// Events
    event FlashMint(
        address indexed receiver,
        address indexed initiator,
        address asset,
        uint256 indexed amount,
        uint256 fee
    );

    event FeeUpdated(uint256 oldFee, uint256 newFee);

    /**
     * @dev Constructor
     * @param _cdxUsdToken The address of the cdxUSD token contract
     * @param _cdxUsdTreasury The address of the cdxUSD treasury
     * @param _fee The percentage of the flash-mint amount that needs to be repaid, on top of the principal (in bps)
     * @param _admin The address of the flashminter admin.
     */
    constructor(address _cdxUsdToken, address _cdxUsdTreasury, uint256 _fee, address _admin)
        Ownable(_admin)
    {
        if (_fee > MAX_FEE) revert CdxUSDFlashMinter__FEE_OUT_OF_RANGE();
        cdxUSD = ICdxUSD(_cdxUsdToken);
        _updateCdxUsdTreasury(_cdxUsdTreasury);
        _updateFee(_fee);
    }

    /// @inheritdoc IERC3156FlashLender
    function flashLoan(
        IERC3156FlashBorrower _receiver,
        address _token,
        uint256 _amount,
        bytes calldata _data
    ) external returns (bool) {
        if (_token != address(cdxUSD)) revert CdxUSDFlashMinter__UNSUPPORTED_ASSET();

        uint256 fee_ = _flashFee(_amount);
        cdxUSD.mint(address(_receiver), _amount);

        if (
            _receiver.onFlashLoan(msg.sender, address(cdxUSD), _amount, fee_, _data)
                != CALLBACK_SUCCESS
        ) revert CdxUSDFlashMinter__CALLBACK_FAILED();

        cdxUSD.transferFrom(address(_receiver), address(this), _amount + fee_);
        cdxUSD.burn(_amount);

        emit FlashMint(address(_receiver), msg.sender, address(cdxUSD), _amount, fee_);

        return true;
    }

    /**
     * @notice Distribute fees to the CdxUsdTreasury
     */
    function distributeFeesToTreasury() external {
        uint256 balance_ = cdxUSD.balanceOf(address(this));
        cdxUSD.transfer(cdxUsdTreasury, balance_);
        emit FeesDistributedToTreasury(cdxUsdTreasury, address(cdxUSD), balance_);
    }

    /**
     * @notice Updates the percentage fee. It is the percentage of the flash-minted amount that needs to be repaid.
     * @dev The fee is expressed in bps. A value of 100, results in 1.00%
     * @param _newFee The new percentage fee (in bps)
     */
    function updateFee(uint256 _newFee) external onlyOwner {
        _updateFee(_newFee);
    }

    /**
     * @notice Updates the address of the cdxUSD Treasury
     * @dev WARNING: The CdxUsdTreasury is where revenue fees are sent to. Update carefully
     * @param _newCdxUsdTreasury The address of the CdxUsdTreasury
     */
    function updateCdxUsdTreasury(address _newCdxUsdTreasury) external onlyOwner {
        _updateCdxUsdTreasury(_newCdxUsdTreasury);
    }

    /// @inheritdoc IERC3156FlashLender
    function maxFlashLoan(address _token) external view returns (uint256) {
        if (_token != address(cdxUSD)) {
            return 0;
        } else {
            (uint256 capacity_, uint256 level_) = cdxUSD.getFacilitatorBucket(address(this));
            return capacity_ > level_ ? capacity_ - level_ : 0;
        }
    }

    /// @inheritdoc IERC3156FlashLender
    function flashFee(address _token, uint256 _amount) external view returns (uint256) {
        if (_token != address(cdxUSD)) revert CdxUSDFlashMinter__UNSUPPORTED_ASSET();
        return _flashFee(_amount);
    }

    /**
     * @notice Returns the percentage of each flash mint taken as a fee
     * @return The percentage fee of the flash-minted amount that needs to be repaid, on top of the principal (in bps).
     */
    function getFee() external view returns (uint256) {
        return fee;
    }
    /**
     * @notice Returns the address of the cdxUSD Treasury
     * @return The address of the GhoTreasury contract
     */

    function getCdxUsdTreasury() external view returns (address) {
        return cdxUsdTreasury;
    }

    function _flashFee(uint256 _amount) internal view returns (uint256) {
        return _amount.percentMul(fee);
    }

    function _updateFee(uint256 _newFee) internal {
        if (_newFee > MAX_FEE) revert CdxUSDFlashMinter__FEE_OUT_OF_RANGE();
        uint256 oldFee_ = fee;
        fee = _newFee;
        emit FeeUpdated(oldFee_, _newFee);
    }

    function _updateCdxUsdTreasury(address _newCdxUsdTreasury) internal {
        address oldCdxUsdTreasury_ = cdxUsdTreasury;
        cdxUsdTreasury = _newCdxUsdTreasury;
        emit CdxUsdTreasuryUpdated(oldCdxUsdTreasury_, _newCdxUsdTreasury);
    }
}
