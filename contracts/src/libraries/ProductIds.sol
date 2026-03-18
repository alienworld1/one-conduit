// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title ProductIds
/// @notice Canonical productId constants for v1 OneConduit products.
/// @dev productId convention: keccak256(abi.encodePacked("TOKEN:CHAIN:PROTOCOL"))
///      These values are the source of truth — replicate them in the frontend's lib/contracts.ts.
///      Never change these after deployment; changing a productId breaks all registered adapters.
library ProductIds {
    /// @dev Local USDC lending on Polkadot Hub, v1.
    bytes32 internal constant USDC_HUB_LENDING_V1 = keccak256(abi.encodePacked("USDC:HUB:lending-v1"));

    /// @dev XCM DOT liquid staking via Bifrost vDOT, v1.
    bytes32 internal constant DOT_BIFROST_VDOT_V1 = keccak256(abi.encodePacked("DOT:BIFROST:vdot-v1"));
}
