// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title IRiskOracle
/// @notice On-chain risk scoring for registered yield products.
/// @dev Returns 0 for any productId that has not been scored via updateScore().
///      Score of 0 means "unscored", not "zero risk".
interface IRiskOracle {
    function getScore(bytes32 productId) external view returns (uint256 score);

    function updateScore(
        bytes32 productId,
        uint256 apyBps,
        uint256 tvlUSD,
        uint256 utilizationBps,
        uint256 contractAgeDays
    ) external returns (uint256 newScore);
}
