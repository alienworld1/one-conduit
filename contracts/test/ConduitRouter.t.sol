// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {ConduitRouter, RiskScoreTooLow, NotImplemented, NotConfigured, DepositReturnedZero, Deposited, Withdrawn} from "../src/ConduitRouter.sol";
import {ConduitRegistry, AdapterInfo, ProductNotFound} from "../src/ConduitRegistry.sol";
import {LocalLendingAdapter} from "../src/LocalLendingAdapter.sol";
import {MockLendingPool} from "../src/MockLendingPool.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {MockYieldToken} from "../src/mocks/MockYieldToken.sol";
import {ProductIds} from "../src/libraries/ProductIds.sol";
import {MockRiskOracle} from "./mocks/MockRiskOracle.sol";

// File-level symbols in scope via transitive imports:
//   ProductNotFound (ConduitRegistry.sol)
//   RiskScoreTooLow, SettleNotImplemented (ConduitRouter.sol)
//   Deposited (ConduitRouter.sol — event; bytes32 second param distinguishes it from
//              MockLendingPool's Deposited event, which takes address as second param)

contract ConduitRouterTest is Test {
    ConduitRouter router;
    ConduitRegistry reg;
    LocalLendingAdapter adapter;
    MockLendingPool pool;
    MockERC20 underlying;
    MockRiskOracle oracle;

    address constant alice = address(0xA11CE);

    bytes32 constant PRODUCT = ProductIds.USDC_HUB_LENDING_V1;
    uint256 constant USER_BALANCE = 10_000e6;
    uint256 constant DEFAULT_AMOUNT = 1_000e6;
    uint256 constant DEFAULT_SCORE = 75;
    uint256 constant DEFAULT_MIN = 50;

    function setUp() public {
        // Token + pool
        underlying = new MockERC20("Mock USDC", "mUSDC");
        pool = new MockLendingPool(address(underlying), 500); // 5% APY

        // Registry + oracle + router
        reg = new ConduitRegistry();
        oracle = new MockRiskOracle();
        router = new ConduitRouter(address(reg), address(oracle));

        // Adapter — pass registry=address(0) to skip pushMetadata in unit tests
        adapter = new LocalLendingAdapter(address(pool), address(0), PRODUCT);

        // Register adapter in registry
        reg.registerAdapter(
            PRODUCT,
            address(adapter),
            "USDC Hub Lending v1",
            false
        );

        // Healthy risk score
        oracle.setScore(PRODUCT, DEFAULT_SCORE);

        // Fund alice
        underlying.mint(alice, USER_BALANCE);
    }

    // ── Helper ────────────────────────────────────────────────────────────────

    function _approveAndDeposit(uint256 amount, uint256 minScore) internal {
        vm.startPrank(alice);
        underlying.approve(address(router), amount);
        router.deposit(PRODUCT, amount, minScore);
        vm.stopPrank();
    }

    // ── Deposit: happy path ───────────────────────────────────────────────────

    function test_deposit_yieldTokensReceivedByUser() public {
        _approveAndDeposit(DEFAULT_AMOUNT, DEFAULT_MIN);

        // At liquidityIndex == 1e18 (block 0): shares == amount exactly
        assertEq(
            MockYieldToken(adapter.yieldToken()).balanceOf(alice),
            DEFAULT_AMOUNT
        );
        assertEq(underlying.balanceOf(alice), USER_BALANCE - DEFAULT_AMOUNT);
    }

    function test_deposit_poolReceivesUnderlying() public {
        _approveAndDeposit(DEFAULT_AMOUNT, DEFAULT_MIN);
        assertEq(pool.totalDeposited(), DEFAULT_AMOUNT);
    }

    function test_deposit_emitsDepositedEvent() public {
        vm.startPrank(alice);
        underlying.approve(address(router), DEFAULT_AMOUNT);

        // 1:1 at block 0 (liquidityIndex == 1e18), so tokensOut == amount
        vm.expectEmit(true, true, false, true);
        emit Deposited(alice, PRODUCT, DEFAULT_AMOUNT, DEFAULT_AMOUNT);
        router.deposit(PRODUCT, DEFAULT_AMOUNT, DEFAULT_MIN);
        vm.stopPrank();
    }

    // ── Risk gate ─────────────────────────────────────────────────────────────

    function test_deposit_riskScoreTooLow_reverts() public {
        oracle.setScore(PRODUCT, 30);

        vm.startPrank(alice);
        underlying.approve(address(router), DEFAULT_AMOUNT);
        vm.expectRevert(
            abi.encodeWithSelector(
                RiskScoreTooLow.selector,
                uint256(30),
                DEFAULT_MIN
            )
        );
        router.deposit(PRODUCT, DEFAULT_AMOUNT, DEFAULT_MIN);
        vm.stopPrank();
    }

    function test_deposit_scoreExactlyAtMinimum_passes() public {
        oracle.setScore(PRODUCT, DEFAULT_MIN);
        _approveAndDeposit(DEFAULT_AMOUNT, DEFAULT_MIN); // equal → passes
        assertEq(
            MockYieldToken(adapter.yieldToken()).balanceOf(alice),
            DEFAULT_AMOUNT
        );
    }

    function test_deposit_zeroMinScore_bypassesGate() public {
        oracle.setScore(PRODUCT, 0); // unscored
        _approveAndDeposit(DEFAULT_AMOUNT, 0); // minRiskScore=0 → no gate
        assertEq(
            MockYieldToken(adapter.yieldToken()).balanceOf(alice),
            DEFAULT_AMOUNT
        );
    }

    // ── Product not found ─────────────────────────────────────────────────────

    function test_deposit_unknownProduct_reverts() public {
        bytes32 unknown = keccak256("UNKNOWN:PRODUCT");
        vm.startPrank(alice);
        underlying.approve(address(router), DEFAULT_AMOUNT);
        vm.expectRevert(
            abi.encodeWithSelector(ProductNotFound.selector, unknown)
        );
        // minRiskScore=0 bypasses risk gate (unknown has no score set) so registry fires
        router.deposit(unknown, DEFAULT_AMOUNT, 0);
        vm.stopPrank();
    }

    function test_deposit_deactivatedProduct_reverts() public {
        reg.deactivateAdapter(PRODUCT);
        vm.startPrank(alice);
        underlying.approve(address(router), DEFAULT_AMOUNT);
        vm.expectRevert(
            abi.encodeWithSelector(ProductNotFound.selector, PRODUCT)
        );
        router.deposit(PRODUCT, DEFAULT_AMOUNT, DEFAULT_MIN);
        vm.stopPrank();
    }

    // ── Withdraw ──────────────────────────────────────────────────────────────

    function test_withdraw_returnsUnderlyingToUser() public {
        _approveAndDeposit(DEFAULT_AMOUNT, DEFAULT_MIN);

        address yt = adapter.yieldToken();
        uint256 shares = MockYieldToken(yt).balanceOf(alice);

        vm.startPrank(alice);
        MockYieldToken(yt).approve(address(router), shares);
        router.withdraw(PRODUCT, shares);
        vm.stopPrank();

        assertEq(MockYieldToken(yt).balanceOf(alice), 0);
        assertEq(underlying.balanceOf(alice), USER_BALANCE); // same block → 1:1
    }

    function test_withdraw_deactivatedProduct_reverts() public {
        _approveAndDeposit(DEFAULT_AMOUNT, DEFAULT_MIN);
        reg.deactivateAdapter(PRODUCT);

        address yt = adapter.yieldToken();
        vm.startPrank(alice);
        MockYieldToken(yt).approve(address(router), DEFAULT_AMOUNT);
        vm.expectRevert(
            abi.encodeWithSelector(ProductNotFound.selector, PRODUCT)
        );
        router.withdraw(PRODUCT, DEFAULT_AMOUNT);
        vm.stopPrank();
    }

    // ── getQuote ──────────────────────────────────────────────────────────────

    function test_getQuote_returnsAdapterQuote() public view {
        // At block 0, liquidityIndex == 1e18, so quote should be 1:1
        uint256 quote = router.getQuote(PRODUCT, 500e6);
        assertEq(quote, 500e6);
        assertEq(router.getQuote(PRODUCT, 0), 0);
    }

    function test_getQuote_unknownProduct_returnsZero() public view {
        bytes32 unknown = keccak256("NOT:EXISTS");
        // getQuote returns 0 for unknown products instead of reverting
        assertEq(router.getQuote(unknown, 100e6), 0);
    }

    // ── settle ────────────────────────────────────────────────────────────────

    // v3: settle() reverts NotConfigured when receiptNFT has not been set on the router.
    // (The old NotImplemented behaviour was the v2 stub — v3 delegates to the adapter.)
    function test_settle_revertsNotConfigured() public {
        vm.expectRevert(NotConfigured.selector);
        router.settle(1, "");
    }

    // ── Approval cleanup & error handling ──────────────────────────────────────

    function test_deposit_noResidualApproval() public {
        _approveAndDeposit(DEFAULT_AMOUNT, DEFAULT_MIN);

        // Verify router has no residual approval for the adapter
        uint256 remaining = underlying.allowance(
            address(router),
            address(adapter)
        );
        assertEq(remaining, 0, "router approval not cleaned up");
    }

    function test_withdraw_emitsWithdrawnEvent() public {
        _approveAndDeposit(DEFAULT_AMOUNT, DEFAULT_MIN);

        address yt = adapter.yieldToken();
        uint256 shares = MockYieldToken(yt).balanceOf(alice);

        vm.startPrank(alice);
        MockYieldToken(yt).approve(address(router), shares);

        vm.expectEmit(true, true, false, true);
        emit Withdrawn(alice, PRODUCT, shares, shares); // 1:1 at block 0
        router.withdraw(PRODUCT, shares);
        vm.stopPrank();
    }

    // ── Registry integration ──────────────────────────────────────────────────

    function test_registeredAdapterInfo() public view {
        AdapterInfo memory info = reg.getAdapter(PRODUCT);
        assertEq(info.adapterAddress, address(adapter));
        assertFalse(info.isXCM);
        assertTrue(info.active);
    }
}
