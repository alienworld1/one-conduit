// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title IYieldAdapter
/// @notice Interface every yield adapter in the OneConduit system must implement.
/// @dev Adapters that do not support a given operation (e.g. withdraw on XCMAdapter v1)
///      must still implement the function — they should revert with a clear error message.
interface IYieldAdapter {
    /// @notice Deposit `amount` of the underlying token on behalf of `recipient`.
    /// @return receiptOrYieldTokens  Yield tokens (local path) or receiptId cast to uint256 (XCM path).
    function deposit(uint256 amount, address recipient) external returns (uint256 receiptOrYieldTokens);

    /// @notice Withdraw `receiptOrYieldAmount` on behalf of `recipient`.
    /// @return assetsOut  Underlying assets returned.
    function withdraw(uint256 receiptOrYieldAmount, address recipient) external returns (uint256 assetsOut);

    /// @notice Current APY in basis points (1 bps = 0.01%).
    function getAPY() external view returns (uint256 apyBps);

    /// @notice Total value locked in USD (no decimals — whole USD units for simplicity).
    function getTVL() external view returns (uint256 tvlUSD);

    /// @notice Utilisation rate in basis points.
    function getUtilizationRate() external view returns (uint256 utilizationBps);

    /// @notice The ERC-20 token this adapter accepts as input.
    function underlyingToken() external view returns (address);

    /// @notice Returns true if this adapter routes via XCM (async, two-phase settlement).
    function isXCM() external view returns (bool);

    /// @notice The ERC-20 token this adapter issues to depositors (yield token / receipt token).
    ///         ConduitRouter uses this to pull yield tokens from the caller on withdrawal.
    function yieldToken() external view returns (address);

    /// @notice Estimate the yield tokens that would be received for a deposit of `amount` underlying.
    /// @param amount  Underlying amount in underlying decimals.
    /// @return estimated  Estimated yield tokens out (same decimals as the yield token).
    function getQuote(uint256 amount) external view returns (uint256 estimated);
}
