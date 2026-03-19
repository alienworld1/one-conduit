// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title ISettleable
/// @notice Interface for yield adapters that support Phase 2 XCM settlement.
/// @dev    XCMAdapter implements this. LocalLendingAdapter does not.
///         ConduitRouter.settle() casts the resolved adapter address to ISettleable
///         before delegating — only XCM products will ever reach this path.
interface ISettleable {
    /// @notice Settle a pending receipt by releasing escrowed funds to the current NFT holder.
    /// @param receiptId  The PendingReceiptNFT token ID to settle.
    /// @param proof      Arbitrary proof bytes — format defined by Module 7.
    ///                   Phase 1 stub reverts unconditionally; Module 7 fills this in.
    function settle(uint256 receiptId, bytes calldata proof) external;
}
