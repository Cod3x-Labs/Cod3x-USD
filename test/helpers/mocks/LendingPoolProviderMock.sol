// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

contract LendingPoolProviderMock {
    address _lendingPool;

    constructor(address lendingPool) {
        _lendingPool = lendingPool;
    }

    function getLendingPool() external view returns (address) {
        return _lendingPool;
    }
}
