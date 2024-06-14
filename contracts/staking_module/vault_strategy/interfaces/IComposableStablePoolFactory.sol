// SPDX-License-Identifier: UNLICENSED
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

interface IComposableStablePoolFactory {
    function version() external view returns (string memory);

    /**
     * @dev Deploys a new `ComposableStablePool`.
     */
    function create(
        string memory name,
        string memory symbol,
        IERC20[] memory tokens,
        uint256 amplificationParameter,
        IRateProvider[] memory rateProviders,
        uint256[] memory tokenRateCacheDurations,
        bool exemptFromYieldProtocolFeeFlag,
        uint256 swapFeePercentage,
        address owner,
        bytes32 salt
    ) external returns (ComposableStablePool);
}

interface IRateProvider {
    /**
     * @dev Returns an 18 decimal fixed point number that is the exchange rate of the token to some other underlying
     * token. The meaning of this rate depends on the context.
     */
    function getRate() external view returns (uint256);
}

interface ComposableStablePool {
    function getPoolId() external view returns (bytes32);
}
