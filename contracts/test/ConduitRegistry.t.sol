// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {
    ConduitRegistry,
    AdapterInfo,
    ProductView,
    ProductNotFound,
    ProductAlreadyRegistered,
    ZeroAddress,
    ZeroProductId
} from "../src/ConduitRegistry.sol";
import {MockAdapter} from "./mocks/MockAdapter.sol";

contract ConduitRegistryTest is Test {
    ConduitRegistry registry;
    MockAdapter mockAdapter;

    // Test uses address(this) as owner — ConduitRegistry sets owner = msg.sender in constructor.
    address internal nonOwner = makeAddr("nonOwner");
    address internal stranger = makeAddr("stranger");

    // Canonical product IDs used across tests.
    bytes32 internal constant PID1 = keccak256(abi.encodePacked("USDC:HUB:lending-v1"));
    bytes32 internal constant PID2 = keccak256(abi.encodePacked("DOT:BIFROST:vdot-v1"));
    bytes32 internal constant PID3 = keccak256(abi.encodePacked("ETH:HUB:staking-v1"));

    function setUp() public {
        registry = new ConduitRegistry();
        mockAdapter = new MockAdapter();
    }

    // ─── Helpers ───────────────────────────────────────────────────────────────

    /// Register PID1 with mockAdapter as owner (address(this)).
    function _registerPID1() internal {
        registry.registerAdapter(PID1, address(mockAdapter), "USDC Lending v1", false);
    }

    /// Register PID1, PID2, PID3 each with a distinct MockAdapter.
    function _registerThree() internal returns (MockAdapter a1, MockAdapter a2, MockAdapter a3) {
        a1 = new MockAdapter();
        a2 = new MockAdapter();
        a3 = new MockAdapter();
        registry.registerAdapter(PID1, address(a1), "Product 1", false);
        registry.registerAdapter(PID2, address(a2), "Product 2", true);
        registry.registerAdapter(PID3, address(a3), "Product 3", false);
    }

    // ─── Registration ──────────────────────────────────────────────────────────

    function test_registerAdapter_success() public {
        _registerPID1();

        ProductView[] memory products = registry.getAllProducts();
        assertEq(products.length, 1);

        ProductView memory pv = products[0];
        assertEq(pv.productId, PID1);
        assertEq(pv.adapterAddress, address(mockAdapter));
        assertEq(pv.name, "USDC Lending v1");
        assertFalse(pv.isXCM);
        assertEq(pv.apyBps, 0); // no metadata pushed yet
        assertEq(pv.tvlUSD, 0);
        assertEq(pv.utilizationBps, 0);
        assertEq(pv.lastUpdated, 0);
        assertEq(pv.riskScore, 0); // always 0 until Module 4
    }

    function test_registerAdapter_onlyOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert("not owner");
        registry.registerAdapter(PID1, address(mockAdapter), "USDC Lending v1", false);
    }

    function test_registerAdapter_zeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector));
        registry.registerAdapter(PID1, address(0), "Bad Adapter", false);
    }

    function test_registerAdapter_zeroProductId() public {
        vm.expectRevert(abi.encodeWithSelector(ZeroProductId.selector));
        registry.registerAdapter(bytes32(0), address(mockAdapter), "Bad Product", false);
    }

    function test_registerAdapter_duplicate() public {
        _registerPID1();
        // Same productId a second time must revert — even the same adapter address.
        vm.expectRevert(abi.encodeWithSelector(ProductAlreadyRegistered.selector, PID1));
        registry.registerAdapter(PID1, address(mockAdapter), "Duplicate", false);
    }

    // ─── Deactivation ──────────────────────────────────────────────────────────

    function test_deactivateAdapter_success() public {
        _registerPID1();

        registry.deactivateAdapter(PID1);

        // getAllProducts must exclude the deactivated product.
        ProductView[] memory products = registry.getAllProducts();
        assertEq(products.length, 0);

        // getAdapter must revert with ProductNotFound for the deactivated product.
        vm.expectRevert(abi.encodeWithSelector(ProductNotFound.selector, PID1));
        registry.getAdapter(PID1);
    }

    function test_deactivateAdapter_onlyOwner() public {
        _registerPID1();

        vm.prank(nonOwner);
        vm.expectRevert("not owner");
        registry.deactivateAdapter(PID1);
    }

    function test_deactivateAdapter_notFound() public {
        // Never registered — must revert.
        vm.expectRevert(abi.encodeWithSelector(ProductNotFound.selector, PID1));
        registry.deactivateAdapter(PID1);
    }

    // ─── Metadata ──────────────────────────────────────────────────────────────

    function test_pushMetadata_success() public {
        _registerPID1();

        uint256 beforeUpdate = block.timestamp;
        registry.pushMetadata(PID1, 750, 5_000_000, 3000);

        ProductView[] memory products = registry.getAllProducts();
        assertEq(products.length, 1);

        ProductView memory pv = products[0];
        assertEq(pv.apyBps, 750);
        assertEq(pv.tvlUSD, 5_000_000);
        assertEq(pv.utilizationBps, 3000);
        assertGe(pv.lastUpdated, beforeUpdate);
    }

    function test_pushMetadata_onlyOwner() public {
        _registerPID1();

        // A stranger (neither owner nor the registered adapter) must be rejected.
        vm.prank(stranger);
        vm.expectRevert("not owner or adapter");
        registry.pushMetadata(PID1, 750, 5_000_000, 3000);
    }

    /// @dev The adapter itself is allowed to push its own metadata (open question recommendation).
    function test_pushMetadata_adapterCanPush() public {
        _registerPID1();

        vm.prank(address(mockAdapter));
        registry.pushMetadata(PID1, 600, 2_000_000, 4500);

        ProductView[] memory products = registry.getAllProducts();
        assertEq(products[0].apyBps, 600);
    }

    function test_pushMetadata_inactiveProduct() public {
        _registerPID1();
        registry.deactivateAdapter(PID1);

        vm.expectRevert(abi.encodeWithSelector(ProductNotFound.selector, PID1));
        registry.pushMetadata(PID1, 750, 5_000_000, 3000);
    }

    // ─── Enumeration ───────────────────────────────────────────────────────────

    function test_getAllProducts_empty() public view {
        ProductView[] memory products = registry.getAllProducts();
        assertEq(products.length, 0);
    }

    function test_getAllProducts_multipleProducts() public {
        (MockAdapter a1, MockAdapter a2,) = _registerThree();

        // Deactivate PID3.
        registry.deactivateAdapter(PID3);

        ProductView[] memory products = registry.getAllProducts();
        assertEq(products.length, 2);

        // Verify the two returned products are PID1 and PID2 (in registration order).
        assertEq(products[0].productId, PID1);
        assertEq(products[0].adapterAddress, address(a1));
        assertEq(products[1].productId, PID2);
        assertEq(products[1].adapterAddress, address(a2));
        assertTrue(products[1].isXCM);
    }

    function test_getProductCount_includesDeactivated() public {
        _registerThree();
        registry.deactivateAdapter(PID3);

        // Count includes deactivated — total registered is 3.
        assertEq(registry.getProductCount(), 3);
        // Active products via getAllProducts() is 2.
        assertEq(registry.getAllProducts().length, 2);
    }

    // ─── getAdapter ────────────────────────────────────────────────────────────

    function test_getAdapter_active() public {
        _registerPID1();

        AdapterInfo memory info = registry.getAdapter(PID1);
        assertEq(info.adapterAddress, address(mockAdapter));
        assertEq(info.name, "USDC Lending v1");
        assertFalse(info.isXCM);
        assertTrue(info.active);
        assertGt(info.registeredAt, 0);
    }

    function test_getAdapter_deactivated() public {
        _registerPID1();
        registry.deactivateAdapter(PID1);

        vm.expectRevert(abi.encodeWithSelector(ProductNotFound.selector, PID1));
        registry.getAdapter(PID1);
    }

    function test_getAdapter_notRegistered() public {
        vm.expectRevert(abi.encodeWithSelector(ProductNotFound.selector, PID1));
        registry.getAdapter(PID1);
    }
}
