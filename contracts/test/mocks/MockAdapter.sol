// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IYieldAdapter} from "../../src/interfaces/IYieldAdapter.sol";

/// @title MockAdapter
/// @notice Minimal implementation of IYieldAdapter for use in ConduitRegistry tests.
///         Returns hardcoded values. deposit() and withdraw() revert — they are not
///         tested in registry-level tests.
contract MockAdapter is IYieldAdapter {
    function deposit(uint256, address) external pure returns (uint256) {
        revert("mock");
    }

    function withdraw(uint256, address) external pure returns (uint256) {
        revert("mock");
    }

    function getAPY() external pure returns (uint256) {
        return 500; // 5.00%
    }

    function getTVL() external pure returns (uint256) {
        return 1_000_000; // $1,000,000
    }

    function getUtilizationRate() external pure returns (uint256) {
        return 5000; // 50.00%
    }

    function underlyingToken() external pure returns (address) {
        return address(1);
    }

    function isXCM() external pure returns (bool) {
        return false;
    }

    function yieldToken() external pure returns (address) {
        return address(2); // stub — not used in registry-level tests
    }

    function getQuote(uint256 amount) external pure returns (uint256) {
        return amount; // 1:1 mock
    }
}
