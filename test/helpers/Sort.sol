// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;


/// Main import
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IVault} from "contracts/staking_module/vault_strategy/interfaces/IVault.sol";

contract Sort {

    constructor() {}

    // --- simple sort IERC20 ---

    function quickSort(uint[] memory arr, int left, int right) internal pure {
        int i = left;
        int j = right;
        if (i == j) return;
        uint pivot = arr[uint(left + (right - left) / 2)];
        while (i <= j) {
            while (arr[uint(i)] < pivot) i++;
            while (pivot < arr[uint(j)]) j--;
            if (i <= j) {
                (arr[uint(i)], arr[uint(j)]) = (arr[uint(j)], arr[uint(i)]);
                i++;
                j--;
            }
        }
        if (left < j)
            quickSort(arr, left, j);
        if (i < right)
            quickSort(arr, i, right);
    }

    function sortUint(uint[] memory data) internal pure returns (uint[] memory) {
        quickSort(data, int(0), int(data.length - 1));
        return data;
    }

    function sort(IERC20[] memory data) public pure returns (IERC20[] memory retIERC20) {
        uint256[] memory arr = new uint256[](data.length);
        retIERC20 = new IERC20[](data.length);

        for (uint i = 0; i < data.length; i++) {
            arr[i] = uint256(uint160(address(data[i])));
        }

        arr = sortUint(arr);

        for (uint i = 0; i < data.length; i++) {
            retIERC20[i] = IERC20(address(uint160((arr[i]))));
        }
    }

    // --- double sort IERC20 and amount ---
    
    function quickSort(uint[] memory arr, uint[] memory arr2, int left, int right) internal pure {
        int i = left;
        int j = right;
        if (i == j) return;
        uint pivot = arr[uint(left + (right - left) / 2)];
        while (i <= j) {
            while (arr[uint(i)] < pivot) i++;
            while (pivot < arr[uint(j)]) j--;
            if (i <= j) {
                (arr[uint(i)], arr[uint(j)]) = (arr[uint(j)], arr[uint(i)]);
                (arr2[uint(i)], arr2[uint(j)]) = (arr2[uint(j)], arr2[uint(i)]);
                i++;
                j--;
            }
        }
        if (left < j)
            quickSort(arr, arr2, left, j);
        if (i < right)
            quickSort(arr, arr2, i, right);
    }

    function sortUint(uint[] memory data, uint[] memory arr2) internal pure returns (uint[] memory, uint[] memory) {
        quickSort(data, arr2, int(0), int(data.length - 1));
        return (data, arr2);
    }

    function sort(IERC20[] memory data, uint256[] memory amounts) internal pure returns (IERC20[] memory retIERC20, uint256[] memory retAmounts) {
        uint256[] memory arr = new uint256[](data.length);
        retIERC20 = new IERC20[](data.length);
        retAmounts = new uint256[](data.length);

        for (uint i = 0; i < data.length; i++) {
            arr[i] = uint256(uint160(address(data[i])));
        }

        (arr , retAmounts)= sortUint(arr, amounts);

        for (uint i = 0; i < data.length; i++) {
            retIERC20[i] = IERC20(address(uint160((arr[i]))));
        }
    }
}