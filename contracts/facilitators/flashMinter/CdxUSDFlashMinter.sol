// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {PercentageMath} from "lib/granary-v2/contracts/protocol/libraries/math/PercentageMath.sol";
import {IERC3156FlashBorrower} from "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";
import {IERC3156FlashLender} from "@openzeppelin/contracts/interfaces/IERC3156FlashLender.sol";
import {ICdxUSD} from "contracts/tokens/interfaces/ICdxUSD.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title CdxUSDFlashMinter
 * @author Cod3x - Beirao
 * @notice Contract that enables FlashMinting of cdxUSD.
 * @dev Based heavily on the EIP3156 reference implementation.
 * Based on: https://github.com/aave/gho-core/blob/main/src/contracts/facilitators/flashMinter/GhoFlashMinter.sol
 */
contract CdxUSDFlashMinter is IERC3156FlashLender, Ownable {
    using PercentageMath for uint256;

    bytes32 public constant CALLBACK_SUCCESS = keccak256("ERC3156FlashBorrower.onFlashLoan");

    uint256 public constant MAX_FEE = 1e4;

    ICdxUSD public immutable CDXUSD_TOKEN;

    // The flashmint fee, expressed in bps (a value of 10000 results in 100.00%)
    uint256 private _fee;

    // The cdxUSD treasury, the recipient of fee distributions
    address private _cdxUsdTreasury;

    /// Errors
    error CdxUSDFlashMinter__FEE_OUT_OF_RANGE();
    error CdxUSDFlashMinter__UNSUPPORTED_ASSET();
    error CdxUSDFlashMinter__CALLBACK_FAILED();

    /// Events
    event FeeUpdated(uint256 oldFee, uint256 newFee);
    event FlashMint(
        address indexed receiver,
        address indexed initiator,
        address asset,
        uint256 indexed amount,
        uint256 fee
    );
    event FeesDistributedToTreasury(
        address indexed cdxUsdTreasury, address indexed asset, uint256 amount
    );
    event CdxUsdTreasuryUpdated(address indexed oldGhoTreasury, address indexed newGhoTreasury);

    /**
     * @dev Constructor
     * @param cdxUsdToken The address of the cdxUSD token contract
     * @param cdxUsdTreasury The address of the cdxUSD treasury
     * @param fee The percentage of the flash-mint amount that needs to be repaid, on top of the principal (in bps)
     * @param addressesProvider The address of the Aave PoolAddressesProvider
     */
    constructor(
        address cdxUsdToken,
        address cdxUsdTreasury,
        uint256 fee,
        address addressesProvider,
        address admin
    ) Ownable(admin) {
        if (fee > MAX_FEE) revert CdxUSDFlashMinter__FEE_OUT_OF_RANGE();
        CDXUSD_TOKEN = ICdxUSD(cdxUsdToken);
        _updateCdxUsdTreasury(cdxUsdTreasury);
        _updateFee(fee);
    }

    /// @inheritdoc IERC3156FlashLender
    function flashLoan(
        IERC3156FlashBorrower receiver,
        address token,
        uint256 amount,
        bytes calldata data
    ) external returns (bool) {
        if (token != address(CDXUSD_TOKEN)) revert CdxUSDFlashMinter__UNSUPPORTED_ASSET();

        uint256 fee = _flashFee(amount);
        CDXUSD_TOKEN.mint(address(receiver), amount);

        if (
            receiver.onFlashLoan(msg.sender, address(CDXUSD_TOKEN), amount, fee, data)
                != CALLBACK_SUCCESS
        ) revert CdxUSDFlashMinter__CALLBACK_FAILED();

        CDXUSD_TOKEN.transferFrom(address(receiver), address(this), amount + fee);
        CDXUSD_TOKEN.burn(amount);

        emit FlashMint(address(receiver), msg.sender, address(CDXUSD_TOKEN), amount, fee);

        return true;
    }

    /**
     * @notice Distribute fees to the CdxUsdTreasury
     */
    function distributeFeesToTreasury() external {
        uint256 balance = CDXUSD_TOKEN.balanceOf(address(this));
        CDXUSD_TOKEN.transfer(_cdxUsdTreasury, balance);
        emit FeesDistributedToTreasury(_cdxUsdTreasury, address(CDXUSD_TOKEN), balance);
    }

    /**
     * @notice Updates the percentage fee. It is the percentage of the flash-minted amount that needs to be repaid.
     * @dev The fee is expressed in bps. A value of 100, results in 1.00%
     * @param newFee The new percentage fee (in bps)
     */
    function updateFee(uint256 newFee) external onlyOwner {
        _updateFee(newFee);
    }

    /**
     * @notice Updates the address of the cdxUSD Treasury
     * @dev WARNING: The CdxUsdTreasury is where revenue fees are sent to. Update carefully
     * @param newCdxUsdTreasury The address of the CdxUsdTreasury
     */
    function updateCdxUsdTreasury(address newCdxUsdTreasury) external onlyOwner {
        _updateCdxUsdTreasury(newCdxUsdTreasury);
    }

    /// @inheritdoc IERC3156FlashLender
    function maxFlashLoan(address token) external view returns (uint256) {
        if (token != address(CDXUSD_TOKEN)) {
            return 0;
        } else {
            (uint256 capacity, uint256 level) = CDXUSD_TOKEN.getFacilitatorBucket(address(this));
            return capacity > level ? capacity - level : 0;
        }
    }

    /// @inheritdoc IERC3156FlashLender
    function flashFee(address token, uint256 amount) external view returns (uint256) {
        if (token != address(CDXUSD_TOKEN)) revert CdxUSDFlashMinter__UNSUPPORTED_ASSET();
        return _flashFee(amount);
    }

    /**
     * @notice Returns the percentage of each flash mint taken as a fee
     * @return The percentage fee of the flash-minted amount that needs to be repaid, on top of the principal (in bps).
     */
    function getFee() external view returns (uint256) {
        return _fee;
    }
    /**
     * @notice Returns the address of the cdxUSD Treasury
     * @return The address of the GhoTreasury contract
     */

    function getCdxUsdTreasury() external view returns (address) {
        return _cdxUsdTreasury;
    }

    function _flashFee(uint256 amount) internal view returns (uint256) {
        return amount.percentMul(_fee);
    }

    function _updateFee(uint256 newFee) internal {
        if (newFee > MAX_FEE) revert CdxUSDFlashMinter__FEE_OUT_OF_RANGE();
        uint256 oldFee = _fee;
        _fee = newFee;
        emit FeeUpdated(oldFee, newFee);
    }

    function _updateCdxUsdTreasury(address newCdxUsdTreasury) internal {
        address oldCdxUsdTreasury = _cdxUsdTreasury;
        _cdxUsdTreasury = newCdxUsdTreasury;
        emit CdxUsdTreasuryUpdated(oldCdxUsdTreasury, newCdxUsdTreasury);
    }
}
