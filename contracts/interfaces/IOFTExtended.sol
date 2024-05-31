// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IOFT} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFTCore.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

interface IOFTExtended is IOFT, IERC20 /*, IERC20Permit */ {
    // ======================= Errors ================================

    error OFTExtended__ONLY_ADMINS();
    error OFTExtended__BRIDGING_LIMIT_REACHED(uint32 _eid);
    error OFTExtended__BRIDGING_HOURLY_LIMIT_REACHED(uint32 _eid);
    error OFTExtended__BRIDGING_PAUSED();
    error OFTExtended__LIMIT_MUST_BE_NEGATIVE();
    error OFTExtended__FEE_TOO_HIGH();

    // ================================== Events ===================================

    event SetBridgeConfig(
        uint32 indexed _eid, int112 _minBalanceLimit, uint104 _hourlyLimit, uint16 _fee
    );
    event SetTreasury(address _newTreasury);
    event SetGuardian(address _newGuardian);
    event ToggleBridgePause(bool _pause);

    // ======================= Structs ================================

    /// @notice Bridge config to a specific chain ids.
    /// @dev Size 240 bits.
    struct BridgeConfig {
        // Fee charged for bridging out of the hosting chain in BPS.
        uint16 fee;
        // The minimum authorized balance for a specidic EID. (always < O)
        // `abs(minBalanceLimit)` represent the maximum amount of asset that can be bridged out.
        int112 minBalanceLimit;
        // Max amount of assets that can be bridged per hour.
        uint104 hourlyLimit;
    }

    /// @notice Bridge utilization to a specific chain ids.
    /// @dev Size 256 bits.
    /// We are not limited with int112 since 2**103 / 10**18 = 2596148 Md $
    /// We are not limited with Uint104 since 2**103 / 10**18 = 202Md $
    struct BridgeUtilization {
        // Track the balance between the hosting network and a specific chain:
        // balanceUtilization < 0 => more token sent than received
        // balanceUtilization > 0 => more token received than sent
        int112 balance;
        // Max amount of assets that can be bridged per hour.
        uint104 slidingHourlyLimitUtilization;
        // Variable used for hourly limit calculation.
        uint40 lastUsedTimestamp;
    }

    // ======================= Interfaces ================================

    function setBridgeConfig(
        uint32 _eid,
        int112 _minBalanceLimit,
        uint104 _hourlyLimit,
        uint16 _fee
    ) external;

    function setTreasury(address _treasury) external;

    function setGuardian(address _guardian) external;

    function toggleBridgePause() external;

    function getBridgeConfig(uint32 _dstEid) external view returns (BridgeConfig memory);

    function getBridgeUtilization(uint32 _dstEid)
        external
        view
        returns (BridgeUtilization memory);
}
