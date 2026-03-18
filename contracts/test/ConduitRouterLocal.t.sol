// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {ConduitRouter, RiskScoreTooLow, Deposited} from "../src/ConduitRouter.sol";
import {ConduitRegistry, ProductNotFound} from "../src/ConduitRegistry.sol";
import {LocalLendingAdapter} from "../src/LocalLendingAdapter.sol";
import {MockLendingPool} from "../src/MockLendingPool.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockYieldToken} from "../src/mocks/MockYieldToken.sol";
import {ProductIds} from "../src/libraries/ProductIds.sol";
import {MockRiskOracle} from "./mocks/MockRiskOracle.sol";

/*
 * ConduitRouterLocal.t.sol — Module 4 unit tests for the local deposit path.
 *
 * Strategy A: pure mocks — all contracts deployed fresh in setUp(), no Paseo RPC.
 * Fast and deterministic. Covers every test case named in the Module 4 spec.
 *
 * Cross-VM call is tested against MockRiskOracle here. The real ink! RiskOracle
 * call is verified separately via cast against Paseo Passet Hub after deployment.
 */
contract ConduitRouterLocalTest is Test {
    ConduitRouter router;
    ConduitRegistry reg;
    LocalLendingAdapter adapter;
    MockLendingPool pool;
    MockERC20 mockUSDC;
    MockRiskOracle oracle;
    MockYieldToken yt;

    address constant alice = address(0xA11CE);

    bytes32 constant PRODUCT = ProductIds.USDC_HUB_LENDING_V1;
    uint256 constant USER_BALANCE = 10_000e6;
    uint256 constant DEPOSIT_AMOUNT = 1_000e6;
    uint256 constant DEFAULT_SCORE = 75;
    uint256 constant DEFAULT_MIN = 50;

    function setUp() public {
        // Tokens + pool
        mockUSDC = new MockERC20("Mock USDC", "mUSDC");
        pool = new MockLendingPool(address(mockUSDC), 500); // 5% APY
        yt = MockYieldToken(pool.yieldToken());

        // Yield reserve — pool holds extra underlying to cover index-growth payouts.
        // Supply-only mock has no borrowers, so reserve must be seeded manually.
        mockUSDC.mint(address(pool), 1_000_000e6);

        // Infrastructure
        reg = new ConduitRegistry();
        oracle = new MockRiskOracle();
        router = new ConduitRouter(address(reg), address(oracle));

        // Adapter: registry=address(0) disables pushMetadata in unit tests
        adapter = new LocalLendingAdapter(address(pool), address(0), PRODUCT);
        reg.registerAdapter(PRODUCT, address(adapter), "USDC Hub Lending v1", false);

        // Seed healthy score
        oracle.setScore(PRODUCT, DEFAULT_SCORE);

        // Fund alice
        mockUSDC.mint(alice, USER_BALANCE);
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    function _deposit(uint256 amount, uint256 minScore) internal {
        vm.startPrank(alice);
        mockUSDC.approve(address(router), amount);
        router.deposit(PRODUCT, amount, minScore);
        vm.stopPrank();
    }

    // ── Happy path ────────────────────────────────────────────────────────────

    /// @dev US-01: full local deposit executes in one call, yield tokens received.
    function test_deposit_local_success() public {
        _deposit(DEPOSIT_AMOUNT, DEFAULT_MIN);
        assertGt(yt.balanceOf(alice), 0, "no yield tokens received");
    }

    /// @dev tokensOut return value matches actual yield token balance change.
    function test_deposit_yieldsTokensToUser() public {
        uint256 before = yt.balanceOf(alice);
        // At liquidityIndex == 1e18 (fresh pool, same block): tokensOut == DEPOSIT_AMOUNT
        _deposit(DEPOSIT_AMOUNT, DEFAULT_MIN);
        uint256 received = yt.balanceOf(alice) - before;
        assertEq(received, DEPOSIT_AMOUNT, "yield token delta mismatch");
    }

    // ── Risk gate ─────────────────────────────────────────────────────────────

    /// @dev US-06: deposit reverts with RiskScoreTooLow when score < minRiskScore.
    function test_deposit_riskGate_blocked() public {
        oracle.setScore(PRODUCT, 40);

        vm.startPrank(alice);
        mockUSDC.approve(address(router), DEPOSIT_AMOUNT);
        vm.expectRevert(abi.encodeWithSelector(RiskScoreTooLow.selector, uint256(40), uint256(50)));
        router.deposit(PRODUCT, DEPOSIT_AMOUNT, 50);
        vm.stopPrank();
    }

    /// @dev score above minimum passes gate.
    function test_deposit_riskGate_passes() public {
        oracle.setScore(PRODUCT, 80);
        _deposit(DEPOSIT_AMOUNT, 50);
        assertGt(yt.balanceOf(alice), 0);
    }

    /// @dev score == minRiskScore passes gate (boundary: score >= minimum, not score > minimum).
    function test_deposit_riskGate_exactMatch() public {
        oracle.setScore(PRODUCT, 50);
        _deposit(DEPOSIT_AMOUNT, 50);
        assertGt(yt.balanceOf(alice), 0);
    }

    /// @dev unscored product (score=0) with minRiskScore=1 reverts.
    function test_deposit_riskGate_unscored() public {
        oracle.setScore(PRODUCT, 0);

        vm.startPrank(alice);
        mockUSDC.approve(address(router), DEPOSIT_AMOUNT);
        vm.expectRevert(abi.encodeWithSelector(RiskScoreTooLow.selector, uint256(0), uint256(1)));
        router.deposit(PRODUCT, DEPOSIT_AMOUNT, 1);
        vm.stopPrank();
    }

    // ── Registry resolution ───────────────────────────────────────────────────

    /// @dev unknown productId propagates ProductNotFound from the registry.
    function test_deposit_productNotFound() public {
        bytes32 unknown = keccak256("UNKNOWN:PRODUCT");

        vm.startPrank(alice);
        mockUSDC.approve(address(router), DEPOSIT_AMOUNT);
        vm.expectRevert(abi.encodeWithSelector(ProductNotFound.selector, unknown));
        // minRiskScore=0 bypasses risk gate so we reach the registry lookup
        router.deposit(unknown, DEPOSIT_AMOUNT, 0);
        vm.stopPrank();
    }

    /// @dev deactivated product also propagates ProductNotFound (registry handles active check).
    function test_deposit_inactiveProduct() public {
        reg.deactivateAdapter(PRODUCT);

        vm.startPrank(alice);
        mockUSDC.approve(address(router), DEPOSIT_AMOUNT);
        vm.expectRevert(abi.encodeWithSelector(ProductNotFound.selector, PRODUCT));
        router.deposit(PRODUCT, DEPOSIT_AMOUNT, DEFAULT_MIN);
        vm.stopPrank();
    }

    // ── Token flow ────────────────────────────────────────────────────────────

    /// @dev caller's mUSDC balance decreases by exactly the deposited amount.
    function test_deposit_pullsFromCaller() public {
        uint256 before = mockUSDC.balanceOf(alice);
        _deposit(DEPOSIT_AMOUNT, DEFAULT_MIN);
        assertEq(mockUSDC.balanceOf(alice), before - DEPOSIT_AMOUNT);
    }

    /// @dev router holds no residual approval for adapter after deposit completes.
    function test_deposit_noResidualApproval() public {
        _deposit(DEPOSIT_AMOUNT, DEFAULT_MIN);
        assertEq(mockUSDC.allowance(address(router), address(adapter)), 0, "residual approval found");
    }

    /// @dev zero amount reverts inside the pool's ZeroAmount guard (not in the router).
    function test_deposit_zeroAmount() public {
        vm.startPrank(alice);
        mockUSDC.approve(address(router), 0);
        vm.expectRevert(); // pool reverts ZeroAmount; propagates through adapter and router
        router.deposit(PRODUCT, 0, DEFAULT_MIN);
        vm.stopPrank();
    }

    /// @dev user hasn't approved router — transferFrom inside the router reverts.
    function test_deposit_insufficientAllowance() public {
        vm.startPrank(alice);
        // No approve call — router's transferFrom call will hit insufficient allowance
        vm.expectRevert();
        router.deposit(PRODUCT, DEPOSIT_AMOUNT, DEFAULT_MIN);
        vm.stopPrank();
    }

    // ── Withdrawal ────────────────────────────────────────────────────────────

    /// @dev deposit then withdraw; underlying returned to caller, yield tokens burned.
    function test_withdraw_success() public {
        _deposit(DEPOSIT_AMOUNT, DEFAULT_MIN);

        uint256 shares = yt.balanceOf(alice);
        uint256 usdcBefore = mockUSDC.balanceOf(alice);

        vm.startPrank(alice);
        yt.approve(address(router), shares);
        router.withdraw(PRODUCT, shares);
        vm.stopPrank();

        assertEq(yt.balanceOf(alice), 0, "yield tokens not fully redeemed");
        assertGt(mockUSDC.balanceOf(alice), usdcBefore, "no underlying returned");
    }

    /// @dev withdraw more yield tokens than balance — reverts from ERC20 balance check.
    function test_withdraw_moreThanBalance() public {
        // alice has zero yield tokens: any non-zero withdrawal must revert
        vm.startPrank(alice);
        yt.approve(address(router), DEPOSIT_AMOUNT);
        vm.expectRevert();
        router.withdraw(PRODUCT, DEPOSIT_AMOUNT);
        vm.stopPrank();
    }

    // ── getQuote ──────────────────────────────────────────────────────────────

    /// @dev non-zero amount returns a non-zero estimate.
    function test_getQuote_returnsNonZero() public view {
        uint256 estimate = router.getQuote(PRODUCT, DEPOSIT_AMOUNT);
        assertGt(estimate, 0, "quote should be non-zero");
    }

    /// @dev inactive product returns 0 — getQuote must not revert on missing product.
    function test_getQuote_inactiveProduct() public {
        reg.deactivateAdapter(PRODUCT);
        assertEq(router.getQuote(PRODUCT, DEPOSIT_AMOUNT), 0, "should return 0 for inactive product");
    }

    // ── Events ────────────────────────────────────────────────────────────────

    /// @dev Deposited event emitted with exact indexed and data params.
    function test_deposit_emitsDepositedEvent() public {
        vm.startPrank(alice);
        mockUSDC.approve(address(router), DEPOSIT_AMOUNT);

        // At block 0, liquidityIndex == 1e18 → tokensOut == DEPOSIT_AMOUNT exactly (1:1)
        vm.expectEmit(true, true, false, true);
        emit Deposited(alice, PRODUCT, DEPOSIT_AMOUNT, DEPOSIT_AMOUNT);
        router.deposit(PRODUCT, DEPOSIT_AMOUNT, DEFAULT_MIN);
        vm.stopPrank();
    }
}
