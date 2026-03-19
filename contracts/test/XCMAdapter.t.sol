// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {XCMAdapter, ReceiptIdMismatch, NotImplemented, WithdrawalNotSupported, ZeroAmount, XCMDispatched} from "../src/XCMAdapter.sol";
import {
    ConduitRouter,
    NotConfigured,
    ReceiptNotFound,
    ReceiptAlreadySettled,
    InsufficientAllowance
} from "../src/ConduitRouter.sol";
import {ConduitRegistry} from "../src/ConduitRegistry.sol";
import {EscrowVault} from "../src/EscrowVault.sol";
import {PendingReceiptNFT} from "../src/PendingReceiptNFT.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {IXcm} from "../src/interfaces/IXcm.sol";
import {ProductIds} from "../src/libraries/ProductIds.sol";
import {MockRiskOracle} from "./mocks/MockRiskOracle.sol";

// ── Mock XCM Precompile ───────────────────────────────────────────────────────
//
// Etched at the exact precompile address using vm.etch() in setUp().
// Tracks whether execute and weighMessage were called, and stores the last message.
// Mock weight values match plausible on-chain values for assertion clarity.

contract MockXCMPrecompile {
    bool public executeCalled;
    bool public weighMessageCalled;
    bytes public lastMessage;

    uint64 public constant MOCK_REF_TIME = 400_000_000;
    uint64 public constant MOCK_PROOF_SIZE = 65_536;

    function execute(bytes calldata message, IXcm.Weight calldata) external {
        executeCalled = true;
        lastMessage = message;
    }

    function send(bytes calldata, bytes calldata message) external {
        executeCalled = true;
        lastMessage = message;
    }

    function weighMessage(
        bytes calldata
    ) external returns (IXcm.Weight memory) {
        weighMessageCalled = true;
        return IXcm.Weight(MOCK_REF_TIME, MOCK_PROOF_SIZE);
    }
}

// ── Test Contract ─────────────────────────────────────────────────────────────

contract XCMAdapterTest is Test {
    // ── Constants ─────────────────────────────────────────────────────────────
    address internal constant XCM_PRECOMPILE =
        0x00000000000000000000000000000000000a0000;

    bytes32 internal constant XCM_PRODUCT_ID = ProductIds.DOT_BIFROST_VDOT_V1;

    // Placeholder XCM bytes — content doesn't matter for unit tests; the mock precompile
    // accepts any bytes. Use a recognisable sentinel so assertions are readable.
    bytes internal constant XCM_TEMPLATE = hex"deadbeef";

    uint256 internal constant DOT_DECIMALS = 10; // 1 DOT = 10^10 planck
    uint256 internal constant ONE_DOT = 10_000_000_000;
    uint256 internal constant INITIAL_BALANCE = 10_000 * ONE_DOT;
    uint256 internal constant DEPOSIT_AMOUNT = 1_000 * ONE_DOT;

    address internal constant alice = address(0xA11CE);
    address internal constant bob = address(0xB0B);
    address internal constant relayer = address(0xBEEF);

    // ── Contracts ──────────────────────────────────────────────────────────────
    MockERC20 internal mockDOT;
    EscrowVault internal vault;
    PendingReceiptNFT internal nft;
    XCMAdapter internal xcmAdapter;
    MockXCMPrecompile internal xcmAtPrecompile; // cast of the etched address

    // ── setUp ─────────────────────────────────────────────────────────────────

    function setUp() public {
        // 1. Deploy MockERC20 as DOT stand-in (18 decimals OK — we use raw amounts).
        mockDOT = new MockERC20("Mock DOT", "mDOT");

        // 2. Deploy EscrowVault and PendingReceiptNFT.
        vault = new EscrowVault();
        nft = new PendingReceiptNFT();

        // 3. Deploy XCMAdapter (registry=address(0) disables pushMetadata in tests).
        xcmAdapter = new XCMAdapter(
            address(vault),
            address(nft),
            relayer,
            address(mockDOT),
            address(0), // registry — disabled
            XCM_PRODUCT_ID,
            XCM_TEMPLATE
        );

        // 4. Wire EscrowVault and PendingReceiptNFT to the adapter.
        //    These are the two most forgettable steps — forgetting either causes Unauthorized.
        vault.setAdapter(address(xcmAdapter));
        nft.setAdapter(address(xcmAdapter));

        // 5. Etch MockXCMPrecompile at the exact precompile address.
        //    This intercepts all calls to 0x...0a0000 in tests.
        MockXCMPrecompile mockImpl = new MockXCMPrecompile();
        vm.etch(XCM_PRECOMPILE, address(mockImpl).code);
        xcmAtPrecompile = MockXCMPrecompile(XCM_PRECOMPILE);

        // 6. Fund alice and approve xcmAdapter to spend her tokens.
        mockDOT.mint(alice, INITIAL_BALANCE);
        vm.prank(alice);
        mockDOT.approve(address(xcmAdapter), type(uint256).max);
    }

    // ─── Helper ───────────────────────────────────────────────────────────────

    /// @dev Perform a direct deposit on the adapter as alice (bypassing the router).
    function _deposit(uint256 amount) internal returns (uint256 tokenId) {
        vm.prank(alice);
        tokenId = xcmAdapter.deposit(amount, alice);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // Phase 1 deposit — core flow
    // ═══════════════════════════════════════════════════════════════════════════

    function test_deposit_locksInEscrow() public {
        _deposit(DEPOSIT_AMOUNT);
        assertEq(
            vault.getBalance(1),
            DEPOSIT_AMOUNT,
            "escrow balance mismatch"
        );
    }

    function test_deposit_mintsNFT() public {
        _deposit(DEPOSIT_AMOUNT);
        assertEq(nft.ownerOf(1), alice, "NFT not minted to alice");
    }

    function test_deposit_nftMetadata() public {
        _deposit(DEPOSIT_AMOUNT);
        // receipts() is a public mapping getter — returns individual fields, not a struct.
        (bytes32 pid, uint256 amt, address od, uint256 db, bool settled) = nft
            .receipts(1);

        assertEq(pid, XCM_PRODUCT_ID, "productId mismatch");
        assertEq(amt, DEPOSIT_AMOUNT, "amount mismatch");
        assertEq(od, alice, "originalDepositor mismatch");
        assertEq(db, block.number, "dispatchBlock mismatch");
        assertFalse(settled, "settled should be false");
    }

    function test_deposit_callsXCMPrecompile() public {
        _deposit(DEPOSIT_AMOUNT);
        assertTrue(xcmAtPrecompile.executeCalled(), "execute not called");
    }

    function test_deposit_callsWeighMessage() public {
        _deposit(DEPOSIT_AMOUNT);
        assertTrue(
            xcmAtPrecompile.weighMessageCalled(),
            "weighMessage not called"
        );
    }

    function test_deposit_precompileReceivedTemplate() public {
        _deposit(DEPOSIT_AMOUNT);
        assertEq(
            xcmAtPrecompile.lastMessage(),
            XCM_TEMPLATE,
            "wrong XCM template passed"
        );
    }

    function test_deposit_emitsXCMDispatched() public {
        bytes32 expectedHash = keccak256(XCM_TEMPLATE);

        vm.expectEmit(true, true, false, true);
        emit XCMDispatched(
            alice,
            XCM_PRODUCT_ID,
            DEPOSIT_AMOUNT,
            1,
            expectedHash
        );

        _deposit(DEPOSIT_AMOUNT);
    }

    function test_deposit_returnsReceiptId() public {
        uint256 tokenId = _deposit(DEPOSIT_AMOUNT);
        assertEq(tokenId, 1, "first deposit should return tokenId 1");
    }

    // ─── Receipt ID / Escrow ID alignment ─────────────────────────────────────

    function test_receiptIdMatchesEscrowId() public {
        uint256 tokenId = _deposit(DEPOSIT_AMOUNT);
        // Escrow is keyed by receiptId pre-read before mint.
        // Both must use the same ID — mismatch would corrupt the settlement lookup.
        assertEq(
            vault.getBalance(tokenId),
            DEPOSIT_AMOUNT,
            "escrow ID does not match NFT ID"
        );
    }

    function test_multipleDeposits_incrementIds() public {
        uint256 id1 = _deposit(DEPOSIT_AMOUNT);
        uint256 id2 = _deposit(DEPOSIT_AMOUNT);

        assertEq(id1, 1, "first deposit should be ID 1");
        assertEq(id2, 2, "second deposit should be ID 2");

        // Both escrow entries exist with correct amounts.
        assertEq(vault.getBalance(1), DEPOSIT_AMOUNT);
        assertEq(vault.getBalance(2), DEPOSIT_AMOUNT);

        // Both NFTs exist and belong to alice.
        assertEq(nft.ownerOf(1), alice);
        assertEq(nft.ownerOf(2), alice);
    }

    // ─── Token flow ───────────────────────────────────────────────────────────

    function test_deposit_pullsFromCaller() public {
        uint256 before = mockDOT.balanceOf(alice);
        _deposit(DEPOSIT_AMOUNT);
        assertEq(
            mockDOT.balanceOf(alice),
            before - DEPOSIT_AMOUNT,
            "caller balance not reduced"
        );
    }

    function test_deposit_locksInVaultNotAdapter() public {
        _deposit(DEPOSIT_AMOUNT);
        // Tokens must be in the vault, not left sitting in the adapter.
        assertEq(
            mockDOT.balanceOf(address(xcmAdapter)),
            0,
            "adapter should hold no tokens"
        );
        assertEq(
            mockDOT.balanceOf(address(vault)),
            DEPOSIT_AMOUNT,
            "vault should hold tokens"
        );
    }

    function test_deposit_noResidualApprovalToVault() public {
        _deposit(DEPOSIT_AMOUNT);
        // Adapter must zero out its approval to the vault after deposit.
        assertEq(
            mockDOT.allowance(address(xcmAdapter), address(vault)),
            0,
            "residual approval to vault found"
        );
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // IYieldAdapter compliance
    // ═══════════════════════════════════════════════════════════════════════════

    function test_isXCM_returnsTrue() public view {
        assertTrue(xcmAdapter.isXCM());
    }

    function test_getAPY_returns800() public view {
        assertEq(xcmAdapter.getAPY(), 800);
    }

    function test_getTVL_returnsZero() public view {
        assertEq(xcmAdapter.getTVL(), 0);
    }

    function test_getUtilizationRate_returns3000() public view {
        assertEq(xcmAdapter.getUtilizationRate(), 3000);
    }

    function test_underlyingToken_returnsMockDOT() public view {
        assertEq(xcmAdapter.underlyingToken(), address(mockDOT));
    }

    function test_yieldToken_returnsZeroAddress() public view {
        assertEq(xcmAdapter.yieldToken(), address(0));
    }

    function test_getQuote_returnsAmountUnchanged() public view {
        assertEq(xcmAdapter.getQuote(ONE_DOT), ONE_DOT);
        assertEq(xcmAdapter.getQuote(0), 0);
    }

    function test_withdraw_reverts_WithdrawalNotSupported() public {
        vm.expectRevert(WithdrawalNotSupported.selector);
        xcmAdapter.withdraw(1, alice);
    }

    function test_settle_stub_reverts_NotImplemented() public {
        vm.expectRevert(NotImplemented.selector);
        xcmAdapter.settle(1, "");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // Access control / edge cases
    // ═══════════════════════════════════════════════════════════════════════════

    function test_deposit_zeroAmount_reverts() public {
        vm.prank(alice);
        vm.expectRevert(ZeroAmount.selector);
        xcmAdapter.deposit(0, alice);
    }

    function test_deposit_insufficientAllowance_reverts() public {
        // Bob has tokens but has NOT approved the adapter.
        mockDOT.mint(bob, DEPOSIT_AMOUNT);

        vm.prank(bob);
        vm.expectRevert(); // ERC20 insufficient allowance
        xcmAdapter.deposit(DEPOSIT_AMOUNT, bob);
    }

    function test_deposit_revertsIfVaultAdapterNotSet() public {
        // Deploy a fresh vault without calling setAdapter — Unauthorized on deposit.
        EscrowVault freshVault = new EscrowVault();
        PendingReceiptNFT freshNft = new PendingReceiptNFT();

        XCMAdapter isolatedAdapter = new XCMAdapter(
            address(freshVault), // adapter NOT set on this vault
            address(freshNft),
            relayer,
            address(mockDOT),
            address(0),
            XCM_PRODUCT_ID,
            XCM_TEMPLATE
        );
        freshNft.setAdapter(address(isolatedAdapter));
        // Deliberately NOT calling freshVault.setAdapter(address(isolatedAdapter))

        mockDOT.mint(alice, DEPOSIT_AMOUNT);
        vm.startPrank(alice);
        mockDOT.approve(address(isolatedAdapter), DEPOSIT_AMOUNT);
        vm.expectRevert(EscrowVault.Unauthorized.selector);
        isolatedAdapter.deposit(DEPOSIT_AMOUNT, alice);
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ConduitRouter v3 — settle() delegation tests
    // ═══════════════════════════════════════════════════════════════════════════

    function _buildRouter()
        internal
        returns (ConduitRouter router, ConduitRegistry reg)
    {
        MockRiskOracle oracle = new MockRiskOracle();
        reg = new ConduitRegistry();
        router = new ConduitRouter(address(reg), address(oracle));

        // Register XCM adapter.
        reg.registerAdapter(
            XCM_PRODUCT_ID,
            address(xcmAdapter),
            "DOT Bifrost vDOT v1",
            true
        );

        // Set risk score high enough that minRiskScore=0 always passes.
        oracle.setScore(XCM_PRODUCT_ID, 80);

        // Wire NFT to router.
        router.setReceiptNFT(address(nft));
    }

    function test_routerSettle_delegatesToAdapter() public {
        (ConduitRouter router, ) = _buildRouter();

        // Deposit via router — router pulls tokens from alice, approves adapter, calls deposit.
        vm.startPrank(alice);
        mockDOT.approve(address(router), DEPOSIT_AMOUNT);
        router.deposit(XCM_PRODUCT_ID, DEPOSIT_AMOUNT, 0);
        vm.stopPrank();

        // NFT token ID 1 exists and belongs to alice.
        assertEq(nft.ownerOf(1), alice);

        // settle() delegation: router → xcmAdapter.settle() → reverts NotImplemented.
        // That revert PROVES the delegation path reached the adapter's settle() stub.
        vm.expectRevert(NotImplemented.selector);
        router.settle(1, "");
    }

    function test_routerDeposit_insufficientAllowance_revertsWithDetails() public {
        (ConduitRouter router, ) = _buildRouter();

        // Alice has mDOT from setUp but does not approve router here.
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                InsufficientAllowance.selector,
                address(mockDOT),
                DEPOSIT_AMOUNT,
                uint256(0)
            )
        );
        router.deposit(XCM_PRODUCT_ID, DEPOSIT_AMOUNT, 0);
    }

    function test_routerSettle_receiptNotFound() public {
        (ConduitRouter router, ) = _buildRouter();

        // No receipt with ID 999 exists — dispatchBlock == 0 in the zero-struct.
        vm.expectRevert(
            abi.encodeWithSelector(ReceiptNotFound.selector, uint256(999))
        );
        router.settle(999, "");
    }

    function test_routerSettle_alreadySettled() public {
        // Mint a receipt that is already marked settled.
        // We deploy a fresh NFT and set the test contract as its adapter so we can mint freely.
        PendingReceiptNFT settledNft = new PendingReceiptNFT();
        settledNft.setAdapter(address(this)); // test contract = "adapter"

        PendingReceiptNFT.ReceiptData memory data = PendingReceiptNFT
            .ReceiptData({
                productId: XCM_PRODUCT_ID,
                amount: ONE_DOT,
                originalDepositor: alice,
                dispatchBlock: block.number,
                settled: true // already settled
            });
        settledNft.mint(alice, data);

        // Deploy a fresh router pointed at settledNft.
        MockRiskOracle oracle2 = new MockRiskOracle();
        ConduitRegistry reg2 = new ConduitRegistry();
        ConduitRouter router2 = new ConduitRouter(
            address(reg2),
            address(oracle2)
        );
        reg2.registerAdapter(
            XCM_PRODUCT_ID,
            address(xcmAdapter),
            "DOT Bifrost vDOT v1",
            true
        );
        router2.setReceiptNFT(address(settledNft));

        vm.expectRevert(
            abi.encodeWithSelector(ReceiptAlreadySettled.selector, uint256(1))
        );
        router2.settle(1, "");
    }

    function test_routerSettle_notConfigured_reverts() public {
        // Router with receiptNFT not set yet.
        MockRiskOracle oracle = new MockRiskOracle();
        ConduitRegistry reg = new ConduitRegistry();
        ConduitRouter unconfiguredRouter = new ConduitRouter(
            address(reg),
            address(oracle)
        );

        vm.expectRevert(NotConfigured.selector);
        unconfiguredRouter.settle(1, "");
    }

    function test_setReceiptNFT_onlyOwner() public {
        (ConduitRouter router, ) = _buildRouter();

        vm.prank(bob);
        vm.expectRevert(bytes("not owner"));
        router.setReceiptNFT(address(nft));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // pushMetadata — no-op when registry is address(0)
    // ═══════════════════════════════════════════════════════════════════════════

    function test_pushMetadata_noopWhenRegistryZero() public {
        // Should not revert when registry is address(0) — just returns.
        xcmAdapter.pushMetadata();
    }

    function test_pushMetadata_callsRegistry() public {
        // Deploy a registry and a fresh adapter with it wired in.
        ConduitRegistry reg = new ConduitRegistry();
        XCMAdapter adapterWithRegistry = new XCMAdapter(
            address(vault),
            address(nft),
            relayer,
            address(mockDOT),
            address(reg),
            XCM_PRODUCT_ID,
            XCM_TEMPLATE
        );

        // Register adapter so pushMetadata() passes the "only owner or adapter" check.
        reg.registerAdapter(
            XCM_PRODUCT_ID,
            address(adapterWithRegistry),
            "DOT Bifrost vDOT v1",
            true
        );

        adapterWithRegistry.pushMetadata();

        assertEq(reg.cachedAPY(XCM_PRODUCT_ID), 800);
        assertEq(reg.cachedTVL(XCM_PRODUCT_ID), 0);
        assertEq(reg.cachedUtilization(XCM_PRODUCT_ID), 3000);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // Constructor storage verification
    // ═══════════════════════════════════════════════════════════════════════════

    function test_constructor_storesAllAddresses() public view {
        assertEq(xcmAdapter.escrowVault(), address(vault));
        assertEq(xcmAdapter.receiptNFT(), address(nft));
        assertEq(xcmAdapter.relayerAddress(), relayer);
        assertEq(xcmAdapter.underlyingToken_(), address(mockDOT));
        assertEq(xcmAdapter.productId(), XCM_PRODUCT_ID);
        assertEq(xcmAdapter.xcmMessageTemplate(), XCM_TEMPLATE);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // XCM template sanity -- guards against the 0000 suffix regression
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev Regression guard: polkadotXcm.execute call data ends with 0x0000 (Weight{0,0}).
    ///      Those bytes are the maxWeight parameter -- NOT part of the VersionedXcm message.
    ///      Passing them to xcmExecute causes "Invalid message format".
    ///      This test fails if the template ends with two zero bytes.
    function test_xcmTemplate_doesNotEndWithWeightBytes() public view {
        bytes memory tmpl = xcmAdapter.xcmMessageTemplate();
        uint256 len = tmpl.length;
        assertGt(len, 0, "template is empty");
        if (len >= 2) {
            bool endsWithDoubleZero = (uint8(tmpl[len - 2]) == 0x00 && uint8(tmpl[len - 1]) == 0x00);
            assertFalse(
                endsWithDoubleZero,
                "template ends 0x0000: strip trailing maxWeight from polkadotXcm.execute call data"
            );
        }
    }

    /// @dev setXcmTemplate() allows the owner to correct the template without full redeploy.
    function test_setXcmTemplate_ownerCanUpdate() public {
        bytes memory corrected = hex"050800040000000700e40b54020d010000010100"
            hex"e68c52f6bd8985e321d1c81491608ea0af63c577"
            hex"eeeeeeeeeeeeeeeeeeeeeeee";
        xcmAdapter.setXcmTemplate(corrected);
        assertEq(xcmAdapter.xcmMessageTemplate(), corrected, "template not updated");
    }

    /// @dev setXcmTemplate() reverts for non-owners.
    function test_setXcmTemplate_nonOwnerReverts() public {
        vm.prank(bob);
        vm.expectRevert(bytes("not owner"));
        xcmAdapter.setXcmTemplate(hex"deadbeef");
    }

    /// @dev deposit() uses the updated template after setXcmTemplate().
    function test_setXcmTemplate_depositUsesUpdatedTemplate() public {
        bytes memory updated = hex"cafebabe";
        xcmAdapter.setXcmTemplate(updated);
        _deposit(DEPOSIT_AMOUNT);
        assertEq(xcmAtPrecompile.lastMessage(), updated, "precompile did not receive updated template");
    }
}
