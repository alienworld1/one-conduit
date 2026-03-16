// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ConduitRegistry, AdapterInfo} from "./ConduitRegistry.sol";
import {IYieldAdapter}                from "./interfaces/IYieldAdapter.sol";
import {IRiskOracle}                  from "./interfaces/IRiskOracle.sol";
import {IERC20}                       from "./interfaces/IERC20.sol";

/*
 * ConduitRouter — single entry-point for all OneConduit yield operations.
 *
 * Deposit flow:
 *   1. User approves this router to spend their input token.
 *   2. User calls deposit(productId, amount, minRiskScore).
 *   3. Router resolves adapter via ConduitRegistry.
 *   4. Router calls RiskOracle.getScore() — cross-VM call to Rust/ink! contract on PVM.
 *      If score < minRiskScore the tx reverts (risk gate).
 *   5. Router pulls tokens from user, approves adapter, calls adapter.deposit().
 *   6. Adapter pulls tokens from router, interacts with the pool.
 *   7. Deposited event emitted.
 *
 * Withdraw flow:
 *   1. User approves this router to spend yield tokens.
 *   2. User calls withdraw(productId, yieldTokenAmount).
 *   3. Router pulls yield tokens from user, approves adapter, calls adapter.withdraw().
 *
 * settle() — stub for XCM receipt settlement, implemented in Module 4.
 */

// ── Custom errors ─────────────────────────────────────────────────────────────
// ProductNotFound comes from ConduitRegistry.sol (file-level import) — not re-declared here.

error RiskScoreTooLow(uint256 current, uint256 minimum);
error ReceiptNotFound(uint256 receiptId);
error ReceiptAlreadySettled(uint256 receiptId);
error InvalidSettlementProof(uint256 receiptId);
error SettleNotImplemented();

// ── Events ────────────────────────────────────────────────────────────────────

event Deposited(
    address indexed user,
    bytes32 indexed productId,
    uint256 amountIn,
    uint256 tokensOut
);

// XCMDispatched emitted by XCMAdapter in Module 4 — declared here for ABI completeness.
event XCMDispatched(
    address indexed user,
    bytes32 indexed productId,
    uint256 amount,
    uint256 receiptId,
    bytes32 xcmMsgHash
);

event Settled(
    address indexed holder,
    uint256 indexed receiptId,
    uint256 amountReleased
);

// ── Contract ──────────────────────────────────────────────────────────────────

contract ConduitRouter {
    address public immutable registry;
    address public immutable riskOracle;

    constructor(address _registry, address _riskOracle) {
        registry   = _registry;
        riskOracle = _riskOracle;
    }

    // ─── Core actions ─────────────────────────────────────────────────────────

    /// @notice Deposit into any registered yield product.
    /// @param productId     bytes32 product identifier (see ProductIds.sol).
    /// @param amount        Token amount in underlying decimals. Caller must pre-approve router.
    /// @param minRiskScore  Minimum acceptable score (0–100). Reverts if below.
    ///                      Pass 0 to skip the risk gate (score 0 still passes — use with care;
    ///                      see IRiskOracle.sol: score 0 = unscored product, not "safe").
    function deposit(bytes32 productId, uint256 amount, uint256 minRiskScore) external {
        // 1. Resolve adapter — reverts ProductNotFound if inactive or unknown.
        AdapterInfo memory info = ConduitRegistry(registry).getAdapter(productId);
        address adapter = info.adapterAddress;

        // 2. Cross-VM risk check.
        //    bytes32 → uint256 cast is safe (both are 32 bytes; bit pattern preserved).
        //    On PVM this call crosses the Solidity ↔ Rust boundary via ink! v6 Solidity ABI.
        uint256 score = IRiskOracle(riskOracle).getScore(uint256(productId));
        if (score < minRiskScore) revert RiskScoreTooLow(score, minRiskScore);

        // 3. Pull tokens from user to router, then approve adapter to pull from router.
        //    Adapter's deposit() calls transferFrom(router, adapter, amount) internally.
        address token = IYieldAdapter(adapter).underlyingToken();
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        IERC20(token).approve(adapter, amount);

        // 4. Invoke adapter. Returns yield tokens (local) or receiptId cast to uint256 (XCM).
        uint256 tokensOut = IYieldAdapter(adapter).deposit(amount, msg.sender);

        emit Deposited(msg.sender, productId, amount, tokensOut);
    }

    /// @notice Withdraw from a local yield product by redeeming yield tokens.
    ///         Caller must pre-approve this router to spend their yield tokens.
    /// @dev TODO(Module 4): XCM withdrawal path is architecturally out of scope for v1.
    function withdraw(bytes32 productId, uint256 yieldTokenAmount) external {
        AdapterInfo memory info = ConduitRegistry(registry).getAdapter(productId);
        address adapter = info.adapterAddress;

        // Pull yield tokens from user to router, approve adapter to pull from router.
        address yt = IYieldAdapter(adapter).yieldToken();
        IERC20(yt).transferFrom(msg.sender, address(this), yieldTokenAmount);
        IERC20(yt).approve(adapter, yieldTokenAmount);

        IYieldAdapter(adapter).withdraw(yieldTokenAmount, msg.sender);
    }

    /// @notice Static quote estimate for a deposit.
    /// @dev    Returns input amount unchanged (1:1) in Module 3.
    ///         TODO(Module 4): call adapter.getQuote() once the interface supports it.
    function getQuote(bytes32 productId, uint256 amount) external view returns (uint256 estimated) {
        ConduitRegistry(registry).getAdapter(productId); // reverts ProductNotFound if invalid
        return amount;
    }

    /// @notice Settle an XCM pending receipt.
    ///         TODO(Module 4): routes through XCMAdapter; calls EscrowVault.release() + NFT.burn().
    function settle(uint256, bytes calldata) external pure {
        revert SettleNotImplemented();
    }
}
