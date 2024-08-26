// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {IAToken} from "lib/Cod3x-Lend/contracts/interfaces/IAToken.sol";
import {ICdxUSDFacilitators} from "./ICdxUSDFacilitators.sol";

/**
 * @title ICdxUsdAToken
 * @author Cod3x - Beirao
 * @notice Defines the basic interface of the CdxUsdAToken.
 */
interface ICdxUsdAToken is IAToken, ICdxUSDFacilitators {
    /**
     * @notice Sets a reference to the GHO variable debt token.
     * @param cdxUsdVariableDebtToken The address of the CdxUsdVariableDebtToken contract.
     */
    function setVariableDebtToken(address cdxUsdVariableDebtToken) external;

    /**
     * @notice Returns the address of the GHO variable debt token.
     * @return The address of the CdxUsdVariableDebtToken contract.
     */
    function getVariableDebtToken() external view returns (address);

    /**
     * @notice Sets reliquary information for fee distribution.
     * @param reliquary Reliquary address used for staked cdxUSD.
     * @param reliquaryAllocation BPS of cdxUSD fee distributed to staked cdxUSD.
     */
    function setReliquaryInfo(address reliquary, uint256 reliquaryAllocation) external;
}
