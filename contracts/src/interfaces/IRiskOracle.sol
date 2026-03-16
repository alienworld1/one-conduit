// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title IRiskOracle
/// @notice Interface for the RiskOracle Rust/ink! contract deployed on PVM.
/// @dev productId is bytes32 in ConduitRegistry but passed as uint256 here.
///      Cast with: uint256(uint160(bytes20(productId))) — or simply uint256(productId).
///      Both bytes32 and uint256 are 32 bytes; the cast is safe.
///      Returns 0 for any productId that has not been scored via updateScore().
///      Score of 0 = unscored, not "zero risk". Treat it as a deposit blocker.
interface IRiskOracle {
    function getScore(uint256 productId) external view returns (uint256 newScore);

    function updateScore(
        uint256 productId,
        uint256 apyBps,
        uint256 tvlUSD,
        uint256 utilizationBps,
        uint256 contractAgeDays
    ) external returns (uint256 newScore);
}
