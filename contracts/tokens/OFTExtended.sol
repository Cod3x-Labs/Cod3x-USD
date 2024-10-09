// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import {IOFTExtended} from "contracts/interfaces/IOFTExtended.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {OFTCore} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFTCore.sol";

/**
 * @title OFTExtended Contract
 * @author Cod3x - Beirao
 * @dev OFT token that extends the functionality of the OFTCore contract by adding some features:
 *          - Possibility to pause bridge transactions
 *          - Limit bridging rate
 *          - Hourly limit rate
 *          - Possibility to enable fees
 */
abstract contract OFTExtended is IOFTExtended, OFTCore, ERC20, ERC20Permit {
    uint256 internal constant BPS = 10000;

    /// --- Bridge Config ---
    /// @notice Mapping giving the config for a specific EID.
    mapping(uint32 => int256) internal eidToMinBalanceLimit;
    /// @notice Global max amount of assets that can be bridged per hour.
    uint256 public hourlyLimit;
    /// @notice Fee charged for bridging out of the hosting chain in BPS.
    uint256 public fee;

    /// --- Bridge Utilization ---
    /// @notice Mapping giving the balance for a specific EID.
    // Track the balance between the hosting network and a specific chain:
    // balanceUtilization < 0 => more token sent than received
    // balanceUtilization > 0 => more token received than sent
    mapping(uint32 => int256) internal eidToBalanceUtilization;
    /// @notice Max amount of assets that can be bridged per hour.
    uint256 public slidingHourlyLimitUtilization;
    /// @notice Variable used for hourly limit calculation.
    uint256 public lastUsedTimestamp;

    /// --- Vars ---
    /// @notice Pause any bridging operation.
    bool public lzPause;
    /// @notice Guardian address that can toggle pause.
    address public guardian;
    /// @notice treasury address that receives fees.
    address public treasury;

    modifier onlyGuardian() {
        if (msg.sender != guardian) {
            revert OFTExtended__ONLY_ADMINS();
        }
        _;
    }

    /**
     * @dev Constructor for the OFT contract.
     * @param _name The name of the OFT.
     * @param _symbol The symbol of the OFT.
     * @param _lzEndpoint The LayerZero endpoint address.
     * @param _delegate The delegate capable of making OApp configurations inside of the endpoint.
     */
    constructor(
        string memory _name,
        string memory _symbol,
        address _lzEndpoint,
        address _delegate,
        address _treasury,
        address _guardian
    )
        ERC20(_name, _symbol)
        ERC20Permit(_name)
        OFTCore(decimals(), _lzEndpoint, _delegate)
        Ownable(_delegate)
    {
        treasury = _treasury;
        guardian = _guardian;

        emit SetTreasury(_treasury);
        emit SetGuardian(_guardian);
    }

    // ======================= Getters ================================

    function getBalanceLimit(uint32 _dstEid) external view returns (int256) {
        return eidToMinBalanceLimit[_dstEid];
    }

    function getBalanceUtilization(uint32 _dstEid) external view returns (int256) {
        return eidToBalanceUtilization[_dstEid];
    }

    // ======================= Admin Functions ================================

    /**
     * @notice Admin function for modifying the `minBalanceLimit` of a specific network bridge.
     * @dev To pause a specific eid you can set `minBalanceLimit` to 0.
     * @param _eid network to be modified.
     * @param _minBalanceLimit authorized max negative balance. (always < 0)
     */
    function setBalanceLimit(uint32 _eid, int256 _minBalanceLimit) external onlyOwner {
        // `_minBalanceLimit` represent the imbalance limitation. Since we are only limiting the outflow
        // `_minBalanceLimit` must always be negative.
        if (_minBalanceLimit > 0) revert OFTExtended__LIMIT_MUST_BE_NEGATIVE();

        eidToMinBalanceLimit[_eid] = _minBalanceLimit;

        emit SetBalanceLimit(_eid, _minBalanceLimit);
    }
    /**
     *  @notice Admin function for modifying the `hourlyLimit`.
     * @dev set `hourlyLimit` to type(uint256).max will give infinite bridging capacity and skip the check.
     * @param _hourlyLimit authorized max hourly volume.
     */

    function setHourlyLimit(uint256 _hourlyLimit) external onlyOwner {
        if (hourlyLimit != _hourlyLimit) {
            _updateHourlyLimit(0);
        }

        hourlyLimit = _hourlyLimit;

        emit SetHourlyLimit(_hourlyLimit);
    }
    /**
     *  @notice Admin function for modifying the `fee`.
     *  @param _fee fee charged on bridging transactions. (in BPS)
     */

    function setFee(uint256 _fee) external onlyOwner {
        if (_fee > BPS / 10) revert OFTExtended__FEE_TOO_HIGH();
        fee = _fee;

        emit SetFee(_fee);
    }

    /**
     * @notice set treasury address.
     * @dev this address will receive fees.
     * @param _treasury treasury address.
     */
    function setTreasury(address _treasury) external onlyOwner {
        treasury = _treasury;
        emit SetTreasury(_treasury);
    }

    /**
     * @notice set guardian address.
     * @param _guardian guardian address.
     */
    function setGuardian(address _guardian) external onlyOwner {
        guardian = _guardian;
        emit SetGuardian(_guardian);
    }

    /**
     * @notice Pause on the `send()` function.
     * @dev restricted to guardian.
     */
    function pauseBridge() external onlyGuardian {
        lzPause = true;
        emit ToggleBridgePause(true);
    }

    /**
     * @notice Unpause on the `send()` function.
     * @dev restricted to owner.
     */
    function unpauseBridge() external onlyOwner {
        lzPause = false;
        emit ToggleBridgePause(false);
    }

    // ======================= LayerZero override Functions ================================

    /**
     * @dev Retrieves the address of the underlying ERC20 implementation.
     * @return The address of the OFT token.
     *
     * @dev In the case of OFT, address(this) and erc20 are the same contract.
     */
    function token() public view returns (address) {
        return address(this);
    }

    /**
     * @notice Indicates whether the OFT contract requires approval of the 'token()' to send.
     * @return requiresApproval Needs approval of the underlying token implementation.
     *
     * @dev In the case of OFT where the contract IS the token, approval is NOT required.
     */
    function approvalRequired() external pure virtual returns (bool) {
        return false;
    }

    /**
     * @dev Burns tokens from the sender's specified balance.
     * @param _from The address to debit the tokens from.
     * @param _amountLD The amount of tokens to send in local decimals.
     * @param _minAmountLD The minimum amount to send in local decimals.
     * @param _dstEid The destination chain ID.
     * @return amountSentLD_ The amount sent in local decimals.
     * @return amountReceivedLD_ The amount received in local decimals on the remote.
     */
    function _debit(address _from, uint256 _amountLD, uint256 _minAmountLD, uint32 _dstEid)
        internal
        virtual
        override
        returns (uint256 amountSentLD_, uint256 amountReceivedLD_)
    {
        // Pause check
        if (lzPause) revert OFTExtended__BRIDGING_PAUSED();

        (amountSentLD_, amountReceivedLD_) = _debitView(_amountLD, _minAmountLD, _dstEid);

        // Send fee to treasury
        uint256 feeAmt_ = amountSentLD_ - amountReceivedLD_;
        if (feeAmt_ != 0) {
            _transfer(_from, treasury, feeAmt_);
        }

        // Balance check
        {
            int256 balanceUpdate_ = eidToBalanceUtilization[_dstEid] - int256(amountReceivedLD_);
            if (balanceUpdate_ < eidToMinBalanceLimit[_dstEid]) {
                revert OFTExtended__BRIDGING_LIMIT_REACHED(_dstEid);
            }
            eidToBalanceUtilization[_dstEid] = balanceUpdate_;
        }

        // Hourly limit check
        uint256 hourlyLimit_ = hourlyLimit;
        if (hourlyLimit_ != type(uint256).max) {
            _updateHourlyLimit(amountReceivedLD_);

            if (slidingHourlyLimitUtilization > hourlyLimit_) {
                revert OFTExtended__BRIDGING_HOURLY_LIMIT_REACHED(_dstEid);
            }
        }

        _burn(_from, amountReceivedLD_);
    }

    /**
     * @dev Internal function to mock the amount mutation from a OFT debit() operation.
     * @param _amountLD The amount to send in local decimals.
     * @param _minAmountLD The minimum amount to send in local decimals.
     * @param _dstEid Destination chain endpoint ID.
     * @return amountSentLD_ The amount sent, in local decimals.
     * @return amountReceivedLD_ The amount to be received on the remote chain, in local decimals.
     *
     * @dev Fees would be calculated and deducted from the amount to be received on the remote.
     */
    function _debitView(uint256 _amountLD, uint256 _minAmountLD, uint32 _dstEid)
        internal
        view
        override
        returns (uint256 amountSentLD_, uint256 amountReceivedLD_)
    {
        amountSentLD_ = _removeDust(_amountLD);

        // Fee calculation
        uint256 fee_ = fee;
        if (fee_ != 0 && treasury != address(0)) {
            amountReceivedLD_ = _removeDust(amountSentLD_ - (amountSentLD_ * fee_ / BPS));
        } else {
            amountReceivedLD_ = amountSentLD_;
        }

        // Check for slippage.
        if (amountReceivedLD_ < _minAmountLD) {
            revert SlippageExceeded(amountReceivedLD_, _minAmountLD);
        }
    }

    /**
     * @dev Credits tokens to the specified address.
     * @param _to The address to credit the tokens to.
     * @param _amountLD The amount of tokens to credit in local decimals.
     * @dev _srcEid The source chain ID.
     * @return amountReceivedLD_ The amount of tokens ACTUALLY received in local decimals.
     */
    function _credit(address _to, uint256 _amountLD, uint32 _srcEid)
        internal
        virtual
        override
        returns (uint256 amountReceivedLD_)
    {
        // Balance update
        eidToBalanceUtilization[_srcEid] += int256(_amountLD);

        // @dev In the case of NON-default OFT, the _amountLD MIGHT not be == amountReceivedLD.
        _mint(_to, _amountLD);
        return _amountLD;
    }

    /**
     * @dev Update the hourly limit.
     * @param _amount The amount of tokens sent crosschain.
     */
    function _updateHourlyLimit(uint256 _amount) internal {
        uint256 timeElapsed_ = block.timestamp - lastUsedTimestamp;

        uint256 slidingUtilizationDecrease_ = timeElapsed_ * hourlyLimit / 1 hours;

        // Update the sliding utilization, making sure it doesn't become negative
        uint256 slidingHourlyLimitUtilization_ = slidingHourlyLimitUtilization;

        slidingHourlyLimitUtilization = slidingHourlyLimitUtilization_
            - min(slidingUtilizationDecrease_, slidingHourlyLimitUtilization_) + _amount;

        lastUsedTimestamp = block.timestamp;
    }

    // ================================== Helpers ===================================

    function min(uint256 _a, uint256 _b) internal pure returns (uint256) {
        return _a < _b ? _a : _b;
    }
}
