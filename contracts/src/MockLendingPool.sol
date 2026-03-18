// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ILendingPool} from "./interfaces/ILendingPool.sol";
import {MockYieldToken} from "./mocks/MockYieldToken.sol";

/*
 * MockLendingPool — Fake Aave-style lending pool for the OneConduit demo.
 * Implements ILendingPool so LocalLendingAdapter can call through the interface.
 *
 * Yield model: per-block liquidity index growth.
 *   Block time assumption: Paseo ≈ 6 seconds → ~5,256,000 blocks/year.
 *   liquidityIndex starts at 1e18 (= 1.0). Every block it grows by:
 *     ratePerBlock = annualRateBps * 1e18 / (10000 * BLOCKS_PER_YEAR)
 *   Exchange rate at any moment = projected liquidityIndex / 1e18.
 *
 * Share math:
 *   deposit:  shares = amount * 1e18 / liquidityIndex — minted to recipient
 *   withdraw: underlying = shares * liquidityIndex / 1e18 — sent to recipient
 *
 * First depositor at index 1e18 gets shares == amount (1:1). Correct and expected.
 *
 * Supply-only mock — no borrowers, no utilisation-based rate curve, no liquidation.
 */

// ─── Custom Errors ──────────────────────────────────────────────────────────────

error ZeroAmount();

// ─── Events ─────────────────────────────────────────────────────────────────────

event Deposited(address indexed depositor, address indexed recipient, uint256 amount, uint256 shares);

event Withdrawn(address indexed withdrawer, address indexed recipient, uint256 shares, uint256 amount);

// ─── Contract ───────────────────────────────────────────────────────────────────

contract MockLendingPool is ILendingPool {
    // Paseo block time ≈ 6 seconds → ~5,256,000 blocks/year.
    // Used only for yield calculation — not a protocol invariant.
    uint256 private constant BLOCKS_PER_YEAR = 5_256_000;

    address public owner;
    address public underlyingToken; // ILendingPool: underlyingToken()
    address private _yieldToken; // ILendingPool: yieldToken() — avoids name clash

    uint256 public totalDeposited; // raw underlying held by pool (not mark-to-market)
    uint256 public liquidityIndex; // 1e18 = exchange rate 1.0; grows per block
    uint256 public lastUpdateBlock; // block.number at last index update
    uint256 public annualRateBps; // e.g. 500 = 5%, 2000 = 20%

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    constructor(address underlying_, uint256 annualRateBps_) {
        owner = msg.sender;
        underlyingToken = underlying_;
        annualRateBps = annualRateBps_;
        liquidityIndex = 1e18;
        lastUpdateBlock = block.number;

        // Pool deploys its own yield token; pool address = address(this) after construction.
        _yieldToken = address(new MockYieldToken("Conduit Yield Token", "cYLD", address(this)));
    }

    // ── ILendingPool ──────────────────────────────────────────────────────────────

    function yieldToken() external view returns (address) {
        return _yieldToken;
    }

    function getAPY() external view returns (uint256) {
        return annualRateBps;
    }

    function getTVL() external view returns (uint256) {
        return totalDeposited;
    }

    /// @notice Utilisation rate — hardcoded 70% (mock; realistic for a lending protocol).
    function getUtilizationRate() external pure returns (uint256) {
        return 7000;
    }

    /// @notice Deposit underlying in exchange for yield token shares.
    /// @dev Caller must hold `amount` of underlying and have approved this pool.
    ///      Yield tokens are minted directly to `recipient`.
    /// @param amount     Underlying token amount.
    /// @param recipient  Address to receive yield tokens.
    /// @return shares    Yield token amount minted.
    function deposit(uint256 amount, address recipient) external returns (uint256 shares) {
        if (amount == 0) revert ZeroAmount();
        _updateIndex();

        _safeTransferFrom(underlyingToken, msg.sender, address(this), amount);

        // shares = amount * 1e18 / liquidityIndex
        shares = (amount * 1e18) / liquidityIndex;

        MockYieldToken(_yieldToken).mint(recipient, shares);
        totalDeposited += amount;

        emit Deposited(msg.sender, recipient, amount, shares);
    }

    /// @notice Redeem yield token shares for underlying.
    /// @dev Pool burns yield tokens from msg.sender (caller must hold them).
    ///      Underlying is sent directly to `recipient`.
    /// @param sharesAmount  Yield token shares to redeem.
    /// @param recipient     Address to receive underlying.
    /// @return tokensOut    Underlying amount sent to `recipient`.
    function withdraw(uint256 sharesAmount, address recipient) external returns (uint256 tokensOut) {
        if (sharesAmount == 0) revert ZeroAmount();
        _updateIndex();

        tokensOut = (sharesAmount * liquidityIndex) / 1e18;

        // Burn from caller — adapter calls this, adapter holds the yield tokens.
        MockYieldToken(_yieldToken).burn(msg.sender, sharesAmount);

        _safeTransfer(underlyingToken, recipient, tokensOut);

        // Floor at 0 — defensive against rounding at index boundaries.
        totalDeposited = tokensOut > totalDeposited ? 0 : totalDeposited - tokensOut;

        emit Withdrawn(msg.sender, recipient, sharesAmount, tokensOut);
    }

    // ── Extra — not on ILendingPool ───────────────────────────────────────────────

    /// @notice Returns projected current liquidityIndex (1e18 = 1.0 exchange rate).
    /// @dev Computes as-if _updateIndex() ran right now, without storing the result.
    ///      Always reflects the true current rate — safe for frontend polling and vm.roll tests.
    function getExchangeRate() external view returns (uint256) {
        uint256 blocksElapsed = block.number - lastUpdateBlock;
        if (blocksElapsed == 0 || annualRateBps == 0) return liquidityIndex;
        uint256 ratePerBlock = (annualRateBps * 1e18) / (10000 * BLOCKS_PER_YEAR);
        uint256 indexDelta = (liquidityIndex * ratePerBlock * blocksElapsed) / 1e18;
        return liquidityIndex + indexDelta;
    }

    /// @notice Update the annual yield rate. Applies old rate up to this block first.
    function setAnnualRate(uint256 rateBps) external onlyOwner {
        _updateIndex();
        annualRateBps = rateBps;
    }

    // ── Internal ──────────────────────────────────────────────────────────────────

    /// @dev Grow liquidityIndex based on blocks elapsed since last update.
    ///      Called at the top of every state-changing function.
    function _updateIndex() internal {
        uint256 blocksElapsed = block.number - lastUpdateBlock;
        lastUpdateBlock = block.number;

        if (blocksElapsed == 0 || annualRateBps == 0) return;

        // ratePerBlock = annualRateBps * 1e18 / (10000 * BLOCKS_PER_YEAR)
        // indexDelta   = liquidityIndex * ratePerBlock * blocksElapsed / 1e18
        uint256 ratePerBlock = (annualRateBps * 1e18) / (10000 * BLOCKS_PER_YEAR);
        uint256 indexDelta = (liquidityIndex * ratePerBlock * blocksElapsed) / 1e18;
        liquidityIndex += indexDelta;
    }

    function _safeTransferFrom(address token, address from, address to, uint256 amount) internal {
        (bool ok, bytes memory data) = token.call(
            abi.encodeWithSelector(0x23b872dd, from, to, amount) // transferFrom(address,address,uint256)
        );
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "transferFrom failed");
    }

    function _safeTransfer(address token, address to, uint256 amount) internal {
        (bool ok, bytes memory data) = token.call(
            abi.encodeWithSelector(0xa9059cbb, to, amount) // transfer(address,uint256)
        );
        require(ok && (data.length == 0 || abi.decode(data, (bool))), "transfer failed");
    }
}
