// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IAToken} from "lib/Cod3x-Lend/contracts/interfaces/IAToken.sol";
import {ICdxUSDFacilitators} from "./ICdxUSDFacilitators.sol";

/**
 * @title ICdxUsdAToken
 * @author Cod3x - Beirao
 * @notice Defines the basic interface of the GhoAToken
 */
interface ICdxUsdAToken is IAToken, ICdxUSDFacilitators {
    /**
     * @dev Emitted when variable debt contract is set
     * @param variableDebtToken The address of the CdxUsdVariableDebtToken contract
     */
    event VariableDebtTokenSet(address indexed variableDebtToken);

    /**
     * @notice Sets a reference to the GHO variable debt token
     * @param cdxUsdVariableDebtToken The address of the CdxUsdVariableDebtToken contract
     */
    function setVariableDebtToken(address cdxUsdVariableDebtToken) external;

    /**
     * @notice Returns the address of the GHO variable debt token
     * @return The address of the CdxUsdVariableDebtToken contract
     */
    function getVariableDebtToken() external view returns (address);
}
