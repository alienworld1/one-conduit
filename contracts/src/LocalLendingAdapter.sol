// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IYieldAdapter} from "./interfaces/IYieldAdapter.sol";
import {ILendingPool} from "./interfaces/ILendingPool.sol";
import {IERC20} from "./interfaces/IERC20.sol";

/*
 * LocalLendingAdapter — IYieldAdapter wrapper for a Hub-native Aave-style lending pool.
 *
 * Token flow on deposit:
 *   1. ConduitRouter transfers `amount` of underlying directly here.
 *   2. Adapter approves pool to pull the underlying.
 *   3. Adapter calls pool.deposit(amount, recipient) — pool pulls from adapter,
 *      mints yield tokens directly to recipient (no second transfer needed).
 *
 * Token flow on withdraw:
 *   1. ConduitRouter transfers `yieldAmount` of yield tokens directly here.
 *   2. Adapter calls pool.withdraw(yieldAmount, recipient) — pool burns yield tokens
 *      from adapter (msg.sender) and sends underlying to recipient.
 *
 * pushMetadata(): public — anyone may call to refresh the ConduitRegistry APY/TVL cache
 *   from live pool data. No-op if registry is address(0). Registry enforces adapter-only
 *   push rule (msg.sender = this adapter address).
 *
 * getQuote(amount): view — returns estimated yield tokens out based on current exchange rate.
 */

// Minimal registry interface — avoids importing ConduitRegistry and its file-level declarations.
interface IConduitRegistry {
    function pushMetadata(bytes32 productId, uint256 apyBps, uint256 tvlUSD, uint256 utilizationBps) external;
}

// Extended pool interface with getExchangeRate() for quote calculation.
interface IPoolWithExchangeRate is ILendingPool {
    function getExchangeRate() external view returns (uint256);
}

contract LocalLendingAdapter is IYieldAdapter {
    ILendingPool public immutable pool;

    // Optional: set to address(0) to disable auto-metadata push.
    address public immutable registry;
    bytes32 public immutable productId;

    constructor(address _pool, address _registry, bytes32 _productId) {
        pool = ILendingPool(_pool);
        registry = _registry;
        productId = _productId;
    }

    // ─── IYieldAdapter ────────────────────────────────────────────────────────

    function deposit(uint256 amount, address recipient) external returns (uint256 yieldTokensOut) {
        address underlying = pool.underlyingToken();
        // Pull underlying from caller (router or direct caller in tests).
        IERC20(underlying).transferFrom(msg.sender, address(this), amount);
        // Approve pool to pull from this adapter, then deposit.
        IERC20(underlying).approve(address(pool), amount);
        yieldTokensOut = pool.deposit(amount, recipient);
    }

    function withdraw(uint256 yieldAmount, address recipient) external returns (uint256 assetsOut) {
        // Pull yield tokens from caller (router or direct caller in tests).
        // Pool burns from msg.sender (this adapter) when we call pool.withdraw.
        IERC20(pool.yieldToken()).transferFrom(msg.sender, address(this), yieldAmount);
        assetsOut = pool.withdraw(yieldAmount, recipient);
    }

    function getAPY() external view returns (uint256) {
        return pool.getAPY();
    }

    function getTVL() external view returns (uint256) {
        return pool.getTVL();
    }

    function getUtilizationRate() external view returns (uint256) {
        return pool.getUtilizationRate();
    }

    function underlyingToken() external view returns (address) {
        return pool.underlyingToken();
    }

    function isXCM() external pure returns (bool) {
        return false;
    }

    function yieldToken() external view returns (address) {
        return pool.yieldToken();
    }

    // ─── Quote ────────────────────────────────────────────────────────────────

    function getQuote(uint256 amount) external view returns (uint256 estimated) {
        // Estimate yield tokens out based on current exchange rate.
        // shares = amount * 1e18 / currentExchangeRate
        if (amount == 0) return 0;
        uint256 exchangeRate = IPoolWithExchangeRate(address(pool)).getExchangeRate();
        estimated = (amount * 1e18) / exchangeRate;
    }

    // ─── Convenience: push live pool data into ConduitRegistry cache ──────────

    function pushMetadata() external {
        if (registry == address(0)) return;
        IConduitRegistry(registry).pushMetadata(productId, pool.getAPY(), pool.getTVL(), pool.getUtilizationRate());
    }
}
