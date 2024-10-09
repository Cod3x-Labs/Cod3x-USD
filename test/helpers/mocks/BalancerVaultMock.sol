// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "forge-std/console.sol";
import {IVault} from "contracts/interfaces/IVault.sol";

contract BalancerVaultMock {
    mapping(bytes32 => mapping(address => uint256)) _idToTokenAndCash;
    mapping(bytes32 => IERC20[]) _idToTokens;

    constructor(bytes32 poolId, address[] memory tokens, uint256[] memory balances) {
        _setBalancesForTokens(poolId, tokens, balances);
    }

    function setBalancesForTokens(
        bytes32 poolId,
        address[] memory tokens,
        uint256[] memory balances
    ) external {
        _setBalancesForTokens(poolId, tokens, balances);
    }

    function _setBalancesForTokens(
        bytes32 poolId,
        address[] memory tokens,
        uint256[] memory balances
    ) internal {
        delete _idToTokens[poolId];
        for (uint8 idx_ = 0; idx_ < tokens.length; idx_++) {
            _idToTokenAndCash[poolId][tokens[idx_]] = balances[idx_];
            _idToTokens[poolId].push(IERC20(tokens[idx_]));
            // console.log("Pushing: ", _idToTokens[poolId][idx_]);
        }
    }

    function getPoolTokenInfo(bytes32 poolId, IERC20 token)
        external
        view
        returns (uint256 cash, uint256 managed, uint256 blockNumber, address assetManager)
    {
        return (_idToTokenAndCash[poolId][address(token)], 0, 0, address(0));
    }

    function getPoolTokens(bytes32 poolId)
        external
        view
        returns (IERC20[] memory tokens, uint256[] memory balances, uint256 lastChangeBlock)
    {
        tokens = _idToTokens[poolId];
        balances = new uint256[](tokens.length);
        lastChangeBlock = 0;
        for (uint8 i = 0; i < tokens.length; i++) {
            balances[i] = _idToTokenAndCash[poolId][address(tokens[i])];
        }
    }

    function getPool(bytes32 poolId) external view returns (address, IVault.PoolSpecialization) {
        return (address(this), IVault.PoolSpecialization.GENERAL);
    }

    function getBptIndex() external view returns (uint256) {
        return 2;
    }
}
