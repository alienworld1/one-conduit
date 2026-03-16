// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test}                        from "forge-std/Test.sol";
import {LocalLendingAdapter}         from "../src/LocalLendingAdapter.sol";
import {MockLendingPool, ZeroAmount} from "../src/MockLendingPool.sol";
import {MockERC20}                   from "../src/mocks/MockERC20.sol";
import {MockYieldToken}              from "../src/mocks/MockYieldToken.sol";
import {ProductIds}                  from "../src/libraries/ProductIds.sol";

/*
 * LocalLendingAdapterTest — unit tests for LocalLendingAdapter + MockLendingPool.
 *
 * Token approval pattern (LocalLendingAdapter uses transferFrom):
 *   deposit:  caller approves adapter → adapter pulls underlying → approves pool → pool.deposit
 *   withdraw: caller approves adapter → adapter pulls yield tokens → pool.withdraw burns from adapter
 *
 * registry = address(0) throughout — skips pushMetadata. Registry integration verified by deploy script.
 */
contract LocalLendingAdapterTest is Test {
    MockERC20           mockUSDC;
    MockLendingPool     pool;
    LocalLendingAdapter adapter;

    bytes32 internal constant PRODUCT_ID = ProductIds.USDC_HUB_LENDING_V1;

    function setUp() public {
        mockUSDC = new MockERC20("Mock USDC", "mUSDC");
        pool     = new MockLendingPool(address(mockUSDC), 500); // 5% APY

        // 3-param constructor: pool, registry (address(0) disables pushMetadata), productId
        adapter  = new LocalLendingAdapter(address(pool), address(0), PRODUCT_ID);

        // Mint test USDC to address(this) — enough for all tests.
        mockUSDC.mint(address(this), 10_000e6);
        // Seed the pool with a yield reserve. Supply-only mock has no borrowers generating
        // interest, so the pool must hold extra underlying to cover index-growth payouts.
        mockUSDC.mint(address(pool), 1_000_000e6);
    }

    // ─── Helpers ──────────────────────────────────────────────────────────────────

    function _yieldToken() internal view returns (MockYieldToken) {
        return MockYieldToken(pool.yieldToken());
    }

    /// Approve adapter for underlying, deposit, return shares minted.
    function _deposit(uint256 amount) internal returns (uint256 shares) {
        mockUSDC.approve(address(adapter), amount);
        shares = adapter.deposit(amount, address(this));
    }

    /// Approve adapter for yield tokens, withdraw, return underlying received.
    function _withdraw(uint256 shares) internal returns (uint256 underlying) {
        _yieldToken().approve(address(adapter), shares);
        underlying = adapter.withdraw(shares, address(this));
    }

    // ─── Deposit ──────────────────────────────────────────────────────────────────

    function test_deposit_success() public {
        uint256 shares = _deposit(1000e6);

        assertEq(_yieldToken().balanceOf(address(this)), shares);
        assertEq(pool.totalDeposited(), 1000e6);
        assertTrue(shares > 0);
    }

    function test_deposit_zeroAmount() public {
        mockUSDC.approve(address(adapter), 1000e6);
        vm.expectRevert(ZeroAmount.selector);
        adapter.deposit(0, address(this));
    }

    function test_deposit_insufficientAllowance() public {
        // No approval — adapter's transferFrom reverts.
        vm.expectRevert();
        adapter.deposit(1000e6, address(this));
    }

    function test_deposit_returnsShares() public {
        uint256 returnedShares = _deposit(1000e6);
        assertEq(returnedShares, _yieldToken().balanceOf(address(this)));
    }

    // ─── Withdraw ─────────────────────────────────────────────────────────────────

    function test_withdraw_success() public {
        uint256 shares   = _deposit(1000e6);
        uint256 returned = _withdraw(shares);

        // Same block → index unchanged → returned == deposited exactly.
        assertEq(returned, 1000e6);
        assertEq(_yieldToken().balanceOf(address(this)), 0);
    }

    function test_withdraw_moreAfterBlocks() public {
        uint256 shares = _deposit(1000e6);

        vm.roll(block.number + 1000);

        uint256 returned = _withdraw(shares);

        // After 1000 blocks at 5% APY, returned USDC must exceed the deposited amount.
        assertGt(returned, 1000e6);
    }

    function test_withdraw_zeroAmount() public {
        vm.expectRevert(ZeroAmount.selector);
        adapter.withdraw(0, address(this));
    }

    function test_withdraw_insufficientBalance() public {
        // Approve large amount but hold no yield tokens — MockYieldToken.burn reverts.
        _yieldToken().approve(address(adapter), 1000e6);
        vm.expectRevert();
        adapter.withdraw(1000e6, address(this));
    }

    // ─── Exchange Rate / Yield Accrual ────────────────────────────────────────────

    function test_indexGrowsOverBlocks() public {
        uint256 idxBefore = pool.getExchangeRate();

        vm.roll(block.number + 1000);

        // getExchangeRate() projects the current rate — larger without any state call.
        uint256 idxAfter = pool.getExchangeRate();
        assertGt(idxAfter, idxBefore);
    }

    function test_yieldAccrualCalculation() public {
        uint256 shares = _deposit(1000e6);

        // Fast-forward one full Paseo year (~5,256,000 blocks at 6s each).
        vm.roll(block.number + 5_256_000);

        uint256 returned = _withdraw(shares);

        // At 5% APY over ~1 year, expect ≈1050 USDC ± 1%.
        assertGe(returned, 1040e6);
        assertLe(returned, 1060e6);
    }

    // ─── IYieldAdapter interface ──────────────────────────────────────────────────

    function test_getAPY() public view {
        assertEq(adapter.getAPY(), 500);
    }

    function test_getTVL() public {
        _deposit(1000e6);
        assertEq(adapter.getTVL(), 1000e6);
    }

    function test_getUtilizationRate() public view {
        assertEq(adapter.getUtilizationRate(), 7000);
    }

    function test_underlyingToken() public view {
        assertEq(adapter.underlyingToken(), address(mockUSDC));
    }

    function test_isXCM() public view {
        assertFalse(adapter.isXCM());
    }

    // ─── Full cycle ───────────────────────────────────────────────────────────────

    function test_fullDepositWithdrawCycle() public {
        uint256 balanceBefore = mockUSDC.balanceOf(address(this));

        uint256 shares = _deposit(1000e6);
        assertGt(shares, 0);

        vm.roll(block.number + 1000);

        uint256 returned = _withdraw(shares);

        // More USDC returned than deposited.
        assertGt(returned, 1000e6);

        // All yield tokens burned.
        assertEq(_yieldToken().balanceOf(address(this)), 0);

        // Net USDC balance decreased by less than deposit amount (yield retained).
        uint256 balanceAfter = mockUSDC.balanceOf(address(this));
        assertGt(balanceAfter, balanceBefore - 1000e6);
    }
}
