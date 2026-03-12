// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// HelloPVM — proof that the Revive/PVM Solidity pipeline works.
// No imports, no inheritance, no dependencies.
contract HelloPVM {
    function getNumber(uint256 input) external pure returns (uint256) {
        return input + 1;
    }
}
