// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title IPendingReceiptNFT
/// @notice Minimal interface for XCMAdapter and ConduitRouter to interact with PendingReceiptNFT.
/// @dev    Mirrors the ReceiptData struct and the three functions called externally.
///         Do NOT import PendingReceiptNFT.sol directly in router/adapter — circular deps.
interface IPendingReceiptNFT {
    struct ReceiptData {
        bytes32 productId;
        uint256 amount;
        address originalDepositor;
        uint256 dispatchBlock; // 0 means the receipt does not exist (used as existence check)
        bool settled;
    }

    /// @notice Returns receipt metadata for a given token ID.
    ///         Returns a zero-struct (dispatchBlock == 0) for non-existent IDs.
    function receipts(
        uint256 tokenId
    ) external view returns (ReceiptData memory);

    /// @notice Returns the token ID that will be assigned to the NEXT mint call.
    ///         XCMAdapter reads this before calling mint() to pre-compute the escrow key.
    function nextTokenId() external view returns (uint256);

    /// @notice Mint a receipt NFT to `to` with the provided metadata.
    /// @dev    Only callable by the registered adapter (onlyAdapter modifier in implementation).
    /// @return tokenId  The newly minted token ID.
    function mint(
        address to,
        ReceiptData calldata data
    ) external returns (uint256 tokenId);

    /// @notice Returns current owner of a receipt token, reverts if token does not exist.
    function ownerOf(uint256 tokenId) external view returns (address);

    /// @notice Returns whether a receipt has been marked as settled.
    function isSettled(uint256 tokenId) external view returns (bool);

    /// @notice Marks a receipt as settled. Restricted to adapter in implementation.
    function markSettled(uint256 tokenId) external;

    /// @notice Burns a receipt token after it is marked settled.
    function burn(uint256 tokenId) external;
}
