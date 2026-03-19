// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ConduitRegistry, AdapterInfo} from "./ConduitRegistry.sol";
import {IYieldAdapter} from "./interfaces/IYieldAdapter.sol";
import {IRiskOracle} from "./interfaces/IRiskOracle.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {IPendingReceiptNFT} from "./interfaces/IPendingReceiptNFT.sol";
import {ISettleable} from "./interfaces/ISettleable.sol";

/*
 * ConduitRouter v3 — single entry-point for all OneConduit yield operations.
 *
 * v3 changes:
 *   - receiptNFT storage + setReceiptNFT() setter.
 *   - settle() now delegates to the adapter resolved via ConduitRegistry instead of
 *     reverting NotImplemented unconditionally. ConduitRouter reads the productId from
 *     PendingReceiptNFT.receipts(), resolves the adapter, and calls ISettleable.settle().
 *   - NotConfigured() error added for the receiptNFT == address(0) guard.
 *
 * Deposit flow:
 *   1. User approves this router to spend their input token.
 *   2. User calls deposit(productId, amount, minRiskScore).
 *   3. Router resolves adapter via ConduitRegistry.
 *   4. Router calls RiskOracle.getScore().
 *      If score < minRiskScore the tx reverts (risk gate).
 *   5. Router pulls tokens from user, approves adapter, calls adapter.deposit().
 *   6. Adapter pulls tokens from router, interacts with the pool or XCM path.
 *   7. Deposited event emitted.
 *
 * Withdraw flow (local adapters only):
 *   1. User approves this router to spend yield tokens.
 *   2. User calls withdraw(productId, yieldTokenAmount).
 *   3. Router pulls yield tokens from user, approves adapter, calls adapter.withdraw().
 *
 * Settle flow (XCM adapters only):
 *   1. Anyone calls settle(receiptId, proof).
 *   2. Router reads productId from PendingReceiptNFT.receipts(receiptId).
 *   3. Router resolves the adapter via ConduitRegistry.
 *   4. Router delegates to ISettleable(adapter).settle(receiptId, proof).
 *   5. Module 7 fills in the real settle logic inside the adapter.
 */

// ── Custom errors ─────────────────────────────────────────────────────────────
// ProductNotFound comes from ConduitRegistry.sol (file-level import) — not re-declared here.

error RiskScoreTooLow(uint256 current, uint256 minimum);
error DepositReturnedZero(bytes32 productId);
error InsufficientAllowance(address token, uint256 required, uint256 available);
error InsufficientBalance(address token, uint256 required, uint256 available);
error ReceiptNotFound(uint256 receiptId);
error ReceiptAlreadySettled(uint256 receiptId);
error InvalidSettlementProof(uint256 receiptId);
error NotImplemented();
/// @dev Fired by settle() when receiptNFT has not been set yet.
error NotConfigured();

// ── Events ────────────────────────────────────────────────────────────────────

event Deposited(address indexed user, bytes32 indexed productId, uint256 amountIn, uint256 tokensOut);

event Withdrawn(address indexed user, bytes32 indexed productId, uint256 tokensIn, uint256 amountOut);

// XCMDispatched is emitted by XCMAdapter — declared here for ABI completeness.
event XCMDispatched(
    address indexed user, bytes32 indexed productId, uint256 amount, uint256 receiptId, bytes32 xcmMsgHash
);

event Settled(address indexed holder, uint256 indexed receiptId, uint256 amountReleased);

// ── Contract ──────────────────────────────────────────────────────────────────

contract ConduitRouter {
    address public immutable registry;
    address public immutable riskOracle;
    address public owner;

    /// @notice PendingReceiptNFT address — required for settle() to look up productId by receiptId.
    ///         Set post-deploy via setReceiptNFT(). Not passed to constructor to keep v3
    ///         compatible with the existing deployment pattern.
    address public receiptNFT;

    constructor(address _registry, address _riskOracle) {
        registry = _registry;
        riskOracle = _riskOracle;
        owner = msg.sender;
    }

    // ─── Admin ────────────────────────────────────────────────────────────────

    /// @notice Set the PendingReceiptNFT address used by settle().
    /// @dev    Only callable by owner. Can be called multiple times (no one-time guard here —
    ///         the NFT address may need updating if the NFT contract is redeployed).
    function setReceiptNFT(address receiptNFT_) external {
        require(msg.sender == owner, "not owner");
        receiptNFT = receiptNFT_;
    }

    // ─── Core actions ─────────────────────────────────────────────────────────

    /// @notice Deposit into any registered yield product.
    /// @param productId     bytes32 product identifier (see ProductIds.sol).
    /// @param amount        Token amount in underlying decimals. Caller must pre-approve router.
    /// @param minRiskScore  Minimum acceptable score (0–100). Reverts if below.
    ///                      Pass 0 to skip the risk gate (score 0 still passes — use with care;
    ///                      see IRiskOracle.sol: score 0 = unscored product, not "safe").
    function deposit(bytes32 productId, uint256 amount, uint256 minRiskScore) external {
        // 1. Cross-VM risk check.
        uint256 score = IRiskOracle(riskOracle).getScore(productId);
        if (score < minRiskScore) revert RiskScoreTooLow(score, minRiskScore);

        // 2. Resolve adapter — reverts ProductNotFound if inactive or unknown.
        AdapterInfo memory info = ConduitRegistry(registry).getAdapter(productId);
        address adapter = info.adapterAddress;

        // 3. Pull tokens from user to router, then approve adapter to pull from router.
        //    Check transferFrom return value for safety.
        address token = IYieldAdapter(adapter).underlyingToken();
        uint256 allowance = IERC20(token).allowance(msg.sender, address(this));
        if (allowance < amount) {
            revert InsufficientAllowance(token, amount, allowance);
        }
        uint256 balance = IERC20(token).balanceOf(msg.sender);
        if (balance < amount) {
            revert InsufficientBalance(token, amount, balance);
        }

        bool success = IERC20(token).transferFrom(msg.sender, address(this), amount);
        if (!success) revert InsufficientAllowance(token, amount, allowance);

        // 4. Approve adapter and invoke deposit.
        IERC20(token).approve(adapter, amount);
        uint256 tokensOut = IYieldAdapter(adapter).deposit(amount, msg.sender);

        // 5. Safety check: adapter must return non-zero tokens.
        //    For XCMAdapter this is the receipt NFT ID (>= 1). For local adapters it's yield shares.
        if (tokensOut == 0) revert DepositReturnedZero(productId);

        // 6. Clean up approval (safety pattern — don't leave dangling approvals).
        IERC20(token).approve(adapter, 0);

        emit Deposited(msg.sender, productId, amount, tokensOut);
    }

    /// @notice Withdraw from a local yield product by redeeming yield tokens.
    ///         Caller must pre-approve this router to spend their yield tokens.
    /// @dev XCM products do not support withdrawal — adapter.withdraw() reverts WithdrawalNotSupported.
    function withdraw(bytes32 productId, uint256 yieldTokenAmount) external {
        AdapterInfo memory info = ConduitRegistry(registry).getAdapter(productId);
        address adapter = info.adapterAddress;

        // Pull yield tokens from user to router, approve adapter to pull from router.
        address yt = IYieldAdapter(adapter).yieldToken();
        IERC20(yt).transferFrom(msg.sender, address(this), yieldTokenAmount);
        IERC20(yt).approve(adapter, yieldTokenAmount);

        uint256 assetsOut = IYieldAdapter(adapter).withdraw(yieldTokenAmount, msg.sender);

        // Clean up approval
        IERC20(yt).approve(adapter, 0);

        emit Withdrawn(msg.sender, productId, yieldTokenAmount, assetsOut);
    }

    /// @notice Static quote estimate for a deposit.
    /// @dev    Returns 0 if the product is inactive/unknown without reverting (safe for view calls).
    /// @return estimated  Estimated yield tokens out based on current exchange rate.
    function getQuote(bytes32 productId, uint256 amount) external view returns (uint256 estimated) {
        try ConduitRegistry(registry).getAdapter(productId) returns (AdapterInfo memory info) {
            estimated = IYieldAdapter(info.adapterAddress).getQuote(amount);
        } catch {
            // Product not found or inactive — return 0 instead of reverting in view function
            estimated = 0;
        }
    }

    /// @notice Settle a pending XCM receipt by delegating to the product's adapter.
    /// @dev    Reads productId from PendingReceiptNFT, resolves the adapter via ConduitRegistry,
    ///         and calls ISettleable(adapter).settle(receiptId, proof).
    ///         Module 7 implements the real settlement logic inside XCMAdapter.settle().
    ///         For now, delegation reaches XCMAdapter.settle() which reverts NotImplemented.
    /// @param receiptId  PendingReceiptNFT token ID to settle.
    /// @param proof      Settlement proof bytes — format defined by Module 7.
    function settle(uint256 receiptId, bytes calldata proof) external {
        if (receiptNFT == address(0)) revert NotConfigured();

        // Read productId from the NFT to find the correct adapter.
        // receipts() returns a zero-struct for non-existent IDs; dispatchBlock == 0 means not found.
        IPendingReceiptNFT.ReceiptData memory data = IPendingReceiptNFT(receiptNFT).receipts(receiptId);

        if (data.dispatchBlock == 0) revert ReceiptNotFound(receiptId);
        if (data.settled) revert ReceiptAlreadySettled(receiptId);

        // Resolve the adapter registered for this product.
        AdapterInfo memory info = ConduitRegistry(registry).getAdapter(data.productId);

        // Delegate to the adapter's settle function.
        // XCMAdapter.settle() currently reverts NotImplemented — Module 7 fills this in.
        ISettleable(info.adapterAddress).settle(receiptId, proof);
    }

    // ─── Recovery & Safety ────────────────────────────────────────────────────

    /// @notice Recover tokens accidentally sent to this contract.
    /// @dev    Safety valve for tokens stuck in the router between deposit/withdraw.
    ///         Only callable by owner.
    function recoverERC20(address token, uint256 amount) external {
        require(msg.sender == owner, "not owner");
        bool success = IERC20(token).transfer(msg.sender, amount);
        require(success, "transfer failed");
    }
}
