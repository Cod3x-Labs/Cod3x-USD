// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

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

    event SetBalanceLimit(uint32 indexed _eid, int256 _minBalanceLimit);
    event SetFee(uint256 _fee);
    event SetHourlyLimit(uint256 _hourlyLimit);
    event SetTreasury(address _newTreasury);
    event SetGuardian(address _newGuardian);
    event ToggleBridgePause(bool _pause);

    // ======================= Interfaces ================================

    function setBalanceLimit(uint32 _eid, int256 _minBalanceLimit) external;

    function setHourlyLimit(uint256 _hourlyLimit) external;

    function setFee(uint256 _fee) external;

    function setTreasury(address _treasury) external;

    function setGuardian(address _guardian) external;

    function pauseBridge() external;

    function unpauseBridge() external;

    function getBalanceLimit(uint32 _dstEid) external view returns (int256);

    function getBalanceUtilization(uint32 _dstEid) external view returns (int256);
}
