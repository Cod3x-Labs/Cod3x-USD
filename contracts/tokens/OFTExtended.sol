// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IOFTExtended} from "contracts/interfaces/IOFTExtended.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {OFTCore} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFTCore.sol";

/**
 * @title OFTExtended Contract
 * @author Cod3X Labs - Beirao
 * @dev OFT token that extends the functionality of the OFTCore contract by adding some features:
 *          - Possibility to pause bridge transactions
 *          - Limit bridging rate
 *          - Hourly limit rate
 *          - Possibility to enable fees
 */
abstract contract OFTExtended is IOFTExtended, OFTCore, ERC20, ERC20Permit {
    using SafeCast for uint256;
    using SafeCast for int256;

    uint16 internal constant BPS = 10000;

    /// @notice Mapping giving the config for a specific EID.
    mapping(uint32 => BridgeConfig) internal eidToConfig;

    /// @notice Mapping giving the utilization for a specific EID.
    mapping(uint32 => BridgeUtilization) internal eidToUtilization;

    /// @notice Pause any bridging operation.
    bool lzPause;
    /// @notice Guardian address that can toggle pause.
    address public guardian;
    /// @notice treasury address that receives fees.
    address public treasury;

    modifier onlyGuardianOrOwner() {
        if (msg.sender != guardian && msg.sender != owner()) {
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

    function getBridgeConfig(uint32 _dstEid) external view returns (BridgeConfig memory) {
        return eidToConfig[_dstEid];
    }

    function getBridgeUtilization(uint32 _dstEid)
        external
        view
        returns (BridgeUtilization memory)
    {
        return eidToUtilization[_dstEid];
    }

    // ======================= Admin Functions ================================

    /**
     * @notice admin function for modifying the configuration of a specific network bridge.
     * @dev set `hourlyLimit` to type(uint104).max will give infinite bridging capacity and skip the check.
     * @dev To pause a specific eid you can set `_minBalanceLimit` to 0.
     * @param _eid network to be modified.
     * @param _minBalanceLimit authorized max negative balance. (always < 0)
     * @param _hourlyLimit authorized max hourly volume.
     * @param _fee fee charged on bridging transactions. (in BPS)
     */
    function setBridgeConfig(
        uint32 _eid,
        int112 _minBalanceLimit,
        uint104 _hourlyLimit,
        uint16 _fee
    ) external onlyOwner {
        // `eidToConfig._minBalanceLimit` represent the imbalance limitation. Since we are only limiting the outflow
        // `_minBalanceLimit` must always be negative.
        if (_minBalanceLimit > 0) revert OFTExtended__LIMIT_MUST_BE_NEGATIVE();
        if (_fee > BPS / 10) revert OFTExtended__FEE_TOO_HIGH();

        BridgeConfig storage eidToConfigPtr = eidToConfig[_eid];
        eidToConfigPtr.minBalanceLimit = _minBalanceLimit;
        eidToConfigPtr.hourlyLimit = _hourlyLimit;
        eidToConfigPtr.fee = _fee;

        emit SetBridgeConfig(_eid, _minBalanceLimit, _hourlyLimit, _fee);
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
     * @notice toggle pause on the `send()` function.
     * @dev restricted to guardian and owner.
     */
    function toggleBridgePause() external onlyGuardianOrOwner {
        lzPause = !lzPause;
        emit ToggleBridgePause(lzPause);
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
        BridgeConfig storage eidToConfigPtr = eidToConfig[_dstEid];
        BridgeUtilization storage BridgeUtilizationPtr = eidToUtilization[_dstEid];

        // Pause check
        if (lzPause) revert OFTExtended__BRIDGING_PAUSED();

        (amountSentLD_, amountReceivedLD_) = _debitView(_amountLD, _minAmountLD, _dstEid);

        // Send fee to treasury
        uint256 feeAmt_ = amountSentLD_ - amountReceivedLD_;
        if (feeAmt_ != 0) {
            _transfer(msg.sender, treasury, feeAmt_);
        }

        // Balance check
        {
            int112 balanceUpdate_ =
                BridgeUtilizationPtr.balance - int256(amountReceivedLD_).toInt112();
            if (balanceUpdate_ < eidToConfigPtr.minBalanceLimit) {
                revert OFTExtended__BRIDGING_LIMIT_REACHED(_dstEid);
            }
            BridgeUtilizationPtr.balance = balanceUpdate_;
        }

        // Hourly limit check
        if (eidToConfigPtr.hourlyLimit != type(uint104).max) {
            uint40 timeElapsed_ = uint40(block.timestamp) - BridgeUtilizationPtr.lastUsedTimestamp;
            uint104 slidingUtilizationDecrease_ =
                timeElapsed_ * eidToConfigPtr.hourlyLimit / 1 hours;

            // Update the sliding utilization, making sure it doesn't become negative
            uint104 slidingHourlyLimitUtilization_ =
                BridgeUtilizationPtr.slidingHourlyLimitUtilization;

            BridgeUtilizationPtr.slidingHourlyLimitUtilization = slidingHourlyLimitUtilization_
                - min(slidingUtilizationDecrease_, slidingHourlyLimitUtilization_)
                + amountReceivedLD_.toUint104();

            if (BridgeUtilizationPtr.slidingHourlyLimitUtilization > eidToConfigPtr.hourlyLimit) {
                revert OFTExtended__BRIDGING_HOURLY_LIMIT_REACHED(_dstEid);
            }

            BridgeUtilizationPtr.lastUsedTimestamp = uint40(block.timestamp);
        }

        _burn(_from, amountReceivedLD_);
    }

    function _debitView(uint256 _amountLD, uint256 _minAmountLD, uint32 _dstEid)
        internal
        view
        override
        returns (uint256 amountSentLD_, uint256 amountReceivedLD_)
    {
        amountSentLD_ = _removeDust(_amountLD);

        // Fee calculation
        uint16 fee_ = eidToConfig[_dstEid].fee;
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
        BridgeUtilization storage BridgeUtilizationPtr = eidToUtilization[_srcEid];
        BridgeUtilizationPtr.balance += int256(_amountLD).toInt112();

        // @dev In the case of NON-default OFT, the _amountLD MIGHT not be == amountReceivedLD.
        _mint(_to, _amountLD);
        return _amountLD;
    }

    // ================================== Helpers ===================================

    function min(uint104 _a, uint104 _b) internal pure returns (uint104) {
        return _a < _b ? _a : _b;
    }
}
