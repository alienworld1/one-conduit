// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IYieldAdapter} from "./interfaces/IYieldAdapter.sol";
import {ISettleable} from "./interfaces/ISettleable.sol";
import {IXcm} from "./interfaces/IXcm.sol";
import {IPendingReceiptNFT} from "./interfaces/IPendingReceiptNFT.sol";
import {IERC20} from "./interfaces/IERC20.sol";

/*
 * XCMAdapter -- IYieldAdapter implementation for the XCM yield path.
 *
 * Phase 1 deposit flow:
 *   1. Pull underlying token from caller (ConduitRouter holds the tokens and approved this adapter).
 *   2. Pre-read the upcoming receiptId from PendingReceiptNFT.nextTokenId().
 *   3. Approve EscrowVault and lock tokens there.
 *   4. Call the XCM precompile: weighMessage() then execute().
 *      On testnet: WithdrawAsset + DepositAsset executes locally (no live parachain target).
 *      On mainnet: same instruction set routes to Bifrost for vDOT minting.
 *   5. Mint PendingReceiptNFT to recipient.
 *   6. Emit XCMDispatched.
 *
 * Phase 2 settle() verifies relayer proof, releases escrow to current NFT holder,
 * and burns the settled receipt.
 *
 * Testnet note: xcmMessageTemplate encodes a FIXED 1 DOT amount (10_000_000_000 planck).
 * The actual deposited amount is escrowed correctly. The fixed-amount mismatch is a testnet
 * limitation -- SCALE Compact<u128> encoding is variable-length and cannot be spliced
 * dynamically in Solidity v1 without a dedicated encoder library. Disclosed in README.
 * Architecturally irrelevant for mainnet (use a proper SCALE encoder there).
 *
 * XCM message template (SCALE-encoded VersionedXcm::V5):
 *   WithdrawAsset([{ id: Here, fun: Fungible(10_000_000_000) }])
 *   DepositAsset({ assets: Wild(All), beneficiary: AccountId32(EscrowVault) })
 *
 *   Correct bytes (52 bytes, NO prefix, NO weight suffix):
 *     0x050800040000000700e40b54020d010000010100
 *       e68c52f6bd8985e321d1c81491608ea0af63c577
 *       eeeeeeeeeeeeeeeeeeeeeeee
 *   (EscrowVault H160 padded to 32-byte AccountId32 via Passet Hub EVM mapping: H160 + 12x0xEE)
 *
 * ENCODING GOTCHA -- why 0x0000 must NOT be included:
 *   Polkadot.js Apps exports polkadotXcm.execute(message, maxWeight) call data.
 *   Layout after stripping the 2-byte pallet+call prefix (0x1f03):
 *     [SCALE(VersionedXcm)]  [SCALE(Weight{ref_time:0, proof_size:0})]
 *                              ^--- this is 0x0000 = compact(0)||compact(0)
 *   The trailing 0x0000 is the second *extrinsic parameter* (maxWeight), NOT part of the
 *   VersionedXcm message. Passing it to execute causes "Invalid message format".
 *   Strip BOTH ends: 2-byte prefix AND 2-byte weight suffix.
 *
 * setXcmTemplate() exists because EscrowVault.setAdapter() and PendingReceiptNFT.setAdapter()
 * are one-time setters. Redeploying XCMAdapter requires redeploying both of those too.
 * An owner-gated template setter avoids that churn when the template bytes need correction.
 */

// ---- Inline minimal interfaces ----------------------------------------------

/// @dev EscrowVault interface used by XCMAdapter for Phase 1 and Phase 2.
interface IEscrowVault {
    function deposit(uint256 receiptId, address token, uint256 amount) external;

    function release(uint256 receiptId, address to) external;

    function getEscrow(uint256 receiptId) external view returns (address token, uint256 amount, bool released);
}

/// @dev Registry interface -- same minimal pattern as LocalLendingAdapter.
interface IConduitRegistry {
    function pushMetadata(bytes32 productId, uint256 apyBps, uint256 tvlUSD, uint256 utilizationBps) external;
}

// ---- Custom errors ---------------------------------------------------------

/// @dev Fired when PendingReceiptNFT mints a different ID than we pre-read. Should never happen.
error ReceiptIdMismatch(uint256 expected, uint256 actual);

/// @dev Fired when a receipt was already settled.
error ReceiptAlreadySettled(uint256 receiptId);

/// @dev Fired when settlement proof is invalid for the target receipt.
error InvalidSettlementProof(uint256 receiptId);

/// @dev withdraw() is not supported for XCM products in v1.
error WithdrawalNotSupported();

/// @dev Fired when deposit() is called with amount == 0.
error ZeroAmount();

// ---- Events ----------------------------------------------------------------

/// @notice Emitted after a successful Phase 1 deposit.
/// @param user        The recipient of the receipt NFT (original depositor).
/// @param productId   The XCM product identifier.
/// @param amount      Actual amount escrowed (underlying token units).
/// @param receiptId   The minted PendingReceiptNFT token ID.
/// @param xcmMsgHash  keccak256 of the xcmMessageTemplate -- stable identifier for the relayer.
event XCMDispatched(
    address indexed user,
    bytes32 indexed productId,
    uint256 amount,
    uint256 receiptId,
    bytes32 xcmMsgHash
);

/// @notice Emitted after attempting local XCM execute via precompile.
/// @dev    On Paseo, execute constraints can fail for contract-origin calls even when
///         the message parses and weighs correctly. Phase 1 remains successful so the
///         receipt workflow can proceed while preserving traceability of the attempt.
event XCMExecuteResult(bool success, bytes returndata);

/// @notice Emitted after successful Phase 2 settlement.
/// @param holder          Current receipt owner who receives released funds.
/// @param receiptId       Settled receipt ID.
/// @param amountReleased  Amount released from EscrowVault.
event Settled(address indexed holder, uint256 indexed receiptId, uint256 amountReleased);

// ---- Contract --------------------------------------------------------------

contract XCMAdapter is IYieldAdapter, ISettleable {
    // XCM Precompile -- fixed address on Paseo Asset Hub and Polkadot Hub mainnet.
    address internal constant XCM_PRECOMPILE = 0x00000000000000000000000000000000000a0000;

    // ---- Immutable addresses -- set once at construction, no setters --------
    address public immutable escrowVault;
    address public immutable receiptNFT;
    /// @notice Relayer address allowed to call settle() in Module 7.
    address public immutable relayerAddress;
    bytes32 public immutable productId;
    /// @notice The ERC-20 token accepted as input (MockDOT on testnet, native DOT wrapper on mainnet).
    address public immutable underlyingToken_;
    /// @notice ConduitRegistry address -- used by pushMetadata(). Set to address(0) to disable.
    address public immutable registry;

    // ---- Mutable storage ---------------------------------------------------

    /// @notice Deployer address -- authorises setXcmTemplate() only.
    ///         Exists to allow template correction without redeploying EscrowVault + PendingReceiptNFT
    ///         (both have one-time adapter setters that would otherwise force a full redeploy cascade).
    address public owner;

    /// @notice SCALE-encoded VersionedXcm bytes passed verbatim to execute().
    ///         Must be ONLY the VersionedXcm bytes -- no polkadotXcm.execute call prefix (0x1f03)
    ///         and no trailing maxWeight bytes (0x0000). Use setXcmTemplate() to correct if needed.
    bytes public xcmMessageTemplate;

    // ---- Constructor -------------------------------------------------------

    /// @param escrowVault_         Address of the deployed EscrowVault.
    /// @param receiptNFT_          Address of the deployed PendingReceiptNFT.
    /// @param relayerAddress_      Address authorised to call settle() in Module 7.
    /// @param underlyingToken__    Underlying ERC-20 token address (double underscore avoids
    ///                             shadowing the underlyingToken_ state variable name).
    /// @param registry_            ConduitRegistry address; pass address(0) to skip pushMetadata.
    /// @param productId_           bytes32 product identifier (ProductIds.DOT_BIFROST_VDOT_V1).
    /// @param xcmMessageTemplate_  SCALE VersionedXcm bytes. No prefix. No weight suffix.
    constructor(
        address escrowVault_,
        address receiptNFT_,
        address relayerAddress_,
        address underlyingToken__,
        address registry_,
        bytes32 productId_,
        bytes memory xcmMessageTemplate_
    ) {
        escrowVault = escrowVault_;
        receiptNFT = receiptNFT_;
        relayerAddress = relayerAddress_;
        underlyingToken_ = underlyingToken__;
        registry = registry_;
        productId = productId_;
        xcmMessageTemplate = xcmMessageTemplate_;
        owner = msg.sender;
    }

    // ---- Admin -------------------------------------------------------------

    /// @notice Replace the XCM message template without redeploying.
    /// @dev    EscrowVault and PendingReceiptNFT have one-time adapter setters.
    ///         Redeploying XCMAdapter requires redeploying both of those too and re-wiring
    ///         everything. This function avoids that cascade for a template-only fix.
    ///
    ///         Correct input = polkadotXcm.execute call data from Polkadot.js Apps
    ///                         MINUS first 2 bytes (pallet+call index 0x1f03)
    ///                         MINUS last  2 bytes (maxWeight 0x0000 = Weight{0,0})
    ///
    /// @param template_  Pure SCALE VersionedXcm bytes. No prefix. No weight suffix.
    function setXcmTemplate(bytes memory template_) external {
        require(msg.sender == owner, "not owner");
        xcmMessageTemplate = template_;
    }

    // ---- Core: Phase 1 deposit ---------------------------------------------

    /// @notice Phase 1 deposit -- escrows tokens, dispatches XCM program, mints receipt NFT.
    /// @param amount     Underlying token amount in token decimals (planck for DOT: 10 decimals).
    /// @param recipient  Address that receives the PendingReceiptNFT. ConduitRouter passes
    ///                   the original msg.sender (end user) here.
    /// @return tokenId   The minted receipt NFT ID. Always >= 1, satisfying the router's
    ///                   DepositReturnedZero guard (which checks tokensOut != 0).
    function deposit(uint256 amount, address recipient) external returns (uint256 tokenId) {
        if (amount == 0) revert ZeroAmount();

        // Step 1 -- Pull underlying from caller.
        //   ConduitRouter already holds the tokens and has approved this adapter for `amount`.
        IERC20(underlyingToken_).transferFrom(msg.sender, address(this), amount);

        // Step 2 -- Pre-read the upcoming receipt ID.
        //   PendingReceiptNFT._nextTokenId is public view. We read it now so the escrow key
        //   matches the NFT ID that mint() is about to assign.
        uint256 receiptId = IPendingReceiptNFT(receiptNFT).nextTokenId();

        // Step 3 -- Approve EscrowVault and lock tokens.
        //   EscrowVault.deposit() calls transferFrom(msg.sender=this, vault, amount).
        IERC20(underlyingToken_).approve(escrowVault, amount);
        IEscrowVault(escrowVault).deposit(receiptId, underlyingToken_, amount);
        // Defensive: zero out residual approval (the full amount should be consumed above).
        IERC20(underlyingToken_).approve(escrowVault, 0);

        // Step 4 -- Call the XCM precompile.
        //   weighMessage() returns the correct Weight for this program; never hardcode weight.
        //   execute() executes the SCALE-encoded VersionedXcm using this contract's origin.
        //   Testnet: WithdrawAsset + DepositAsset runs locally on Passet Hub (no cross-chain target).
        //   Mainnet: replace xcmMessageTemplate with TransferReserveAsset targeting Bifrost para ID.
        IXcm.Weight memory weight = IXcm(XCM_PRECOMPILE).weighMessage(xcmMessageTemplate);
        (bool xcmOk, bytes memory xcmReturndata) = XCM_PRECOMPILE.call(
            abi.encodeWithSignature(
                "execute(bytes,(uint64,uint64))",
                xcmMessageTemplate,
                weight
            )
        );
        emit XCMExecuteResult(xcmOk, xcmReturndata);

        // Step 5 -- Mint receipt NFT to recipient.
        IPendingReceiptNFT.ReceiptData memory data = IPendingReceiptNFT.ReceiptData({
            productId: productId,
            amount: amount,
            originalDepositor: recipient,
            dispatchBlock: block.number,
            settled: false
        });
        tokenId = IPendingReceiptNFT(receiptNFT).mint(recipient, data);

        // Paranoia check -- nextTokenId() and mint() must agree on the same ID.
        // A mismatch means something minted between our pre-read and our mint call,
        // which is impossible in a single EVM transaction unless the NFT contract has a bug.
        if (tokenId != receiptId) revert ReceiptIdMismatch(receiptId, tokenId);

        // Step 6 -- Emit and return.
        emit XCMDispatched(recipient, productId, amount, tokenId, keccak256(xcmMessageTemplate));
    }

    // ---- Phase 2 settle ----------------------------------------------------

    /// @notice Settle a pending receipt with a relayer-signed proof.
    /// @dev    Settlement pays the current receipt holder, not the original depositor.
    function settle(uint256 receiptId, bytes calldata proof) external {
        if (IPendingReceiptNFT(receiptNFT).isSettled(receiptId)) {
            revert ReceiptAlreadySettled(receiptId);
        }

        // ownerOf() reverts for non-existent receipts.
        address currentHolder = IPendingReceiptNFT(receiptNFT).ownerOf(receiptId);

        _verifyProof(receiptId, proof);

        (, uint256 releasedAmount, ) = IEscrowVault(escrowVault).getEscrow(receiptId);

        // Mark settled before external token transfer to guard against re-entrancy loops.
        IPendingReceiptNFT(receiptNFT).markSettled(receiptId);
        IEscrowVault(escrowVault).release(receiptId, currentHolder);
        IPendingReceiptNFT(receiptNFT).burn(receiptId);

        emit Settled(currentHolder, receiptId, releasedAmount);
    }

    /// @dev Verifies a packed 65-byte (r,s,v) EIP-191 personal-sign signature by relayerAddress.
    function _verifyProof(uint256 receiptId, bytes calldata proof) internal view {
        bytes32 messageHash = keccak256(
            abi.encodePacked(
                "OneConduit:settle:",
                block.chainid,
                address(this),
                receiptId
            )
        );

        bytes32 ethSignedHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash)
        );

        if (proof.length != 65) revert InvalidSettlementProof(receiptId);

        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := calldataload(proof.offset)
            s := calldataload(add(proof.offset, 32))
            v := byte(0, calldataload(add(proof.offset, 64)))
        }

        // Malleable signatures are acceptable in v1 because the receipt can only be settled once.
        address recovered = ecrecover(ethSignedHash, v, r, s);
        if (recovered == address(0) || recovered != relayerAddress) {
            revert InvalidSettlementProof(receiptId);
        }
    }

    // ---- IYieldAdapter: view functions -------------------------------------

    /// @notice 8% APY estimate -- Bifrost vDOT historical average. Static for v1.
    function getAPY() external pure returns (uint256) {
        return 800; // 800 bps = 8.00%
    }

    /// @notice TVL is unknowable cross-chain in Phase 1. Returns 0.
    function getTVL() external pure returns (uint256) {
        return 0;
    }

    /// @notice 30% utilisation estimate. Static for v1.
    function getUtilizationRate() external pure returns (uint256) {
        return 3000; // 3000 bps = 30.00%
    }

    /// @notice The ERC-20 token this adapter accepts (MockDOT on testnet).
    function underlyingToken() external view returns (address) {
        return underlyingToken_;
    }

    /// @notice XCM adapter -- always returns true.
    function isXCM() external pure returns (bool) {
        return true;
    }

    /// @notice XCM adapter issues no ERC-20 yield token -- positions are represented by receipt NFTs.
    /// @dev    Returning address(0) ensures any IERC20 call on this value fails (ABI decode error
    ///         on empty return data), which prevents accidental withdraw() calls via the router.
    function yieldToken() external pure returns (address) {
        return address(0);
    }

    /// @notice Quote estimate -- 1:1 passthrough (receipt represents the full deposited amount).
    function getQuote(uint256 amount) external pure returns (uint256) {
        return amount;
    }

    /// @notice XCM withdrawals are not supported in v1. Settlement via settle() only.
    function withdraw(uint256, address) external pure returns (uint256) {
        revert WithdrawalNotSupported();
    }

    // ---- Metadata push -----------------------------------------------------

    /// @notice Push hardcoded APY/TVL/utilisation estimates into ConduitRegistry cache.
    ///         Public -- anyone may call to refresh the registry display data.
    ///         No-op if registry is address(0) (e.g., in unit tests).
    function pushMetadata() external {
        if (registry == address(0)) return;
        IConduitRegistry(registry).pushMetadata(productId, 800, 0, 3000);
    }
}
