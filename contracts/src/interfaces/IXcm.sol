// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title IXcm
/// @notice Interface for the XCM precompile at 0x00000000000000000000000000000000000a0000
///         on Polkadot Hub / Paseo Asset Hub.
/// @dev    Only execute and weighMessage are used in v1. send is included for
///         completeness -- on mainnet with a live parachain target, send would route
///         to Bifrost's para ID. On testnet, execute is used for local execution.
interface IXcm {
    /// @notice Weight struct matching Substrate's Weight type (ref_time + proof_size).
    struct Weight {
        uint64 refTime;
        uint64 proofSize;
    }

    /// @notice Execute a SCALE-encoded VersionedXcm program locally using the caller's origin.
    /// @param message  SCALE-encoded VersionedXcm bytes (NOT ABI-encoded).
    /// @param weight   Maximum weight to allow for execution. Use weighMessage() to get this.
    function execute(
        bytes calldata message,
        Weight calldata weight
    ) external;

    /// @notice Send a SCALE-encoded VersionedXcm message to a remote destination.
    /// @param destination  SCALE-encoded MultiLocation of the destination chain.
    /// @param message      SCALE-encoded VersionedXcm bytes.
    function send(
        bytes calldata destination,
        bytes calldata message
    ) external;

    /// @notice Estimate the weight required to execute a given XCM message.
    /// @param message  SCALE-encoded VersionedXcm bytes.
    /// @return weight  Estimated Weight -- pass directly to execute.
    function weighMessage(
        bytes calldata message
    ) external returns (Weight memory);
}
