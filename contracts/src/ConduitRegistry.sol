// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/*
 * ConduitRegistry — On-chain product catalogue for OneConduit.
 * Single source of truth for which yield products exist, their adapter addresses,
 * and their cached metadata (APY, TVL, utilisation).
 *
 * APY/TVL data uses a push model: adapters or the owner call pushMetadata() to update
 * the registry's cache. getAllProducts() reads the cache — it never calls into adapters.
 * This ensures getAllProducts() is always a pure view that cannot revert due to adapter bugs.
 *
 * productId convention: keccak256(abi.encodePacked("TOKEN:CHAIN:PROTOCOL"))
 * Example: keccak256("USDC:HUB:lending-v1"), keccak256("DOT:BIFROST:vdot-v1")
 * Canonical values are in libraries/ProductIds.sol and frontend lib/contracts.ts.
 *
 * Re-registering a deactivated product is NOT allowed. Once deactivated, the productId
 * is permanently retired to prevent subtle routing bugs from ID reuse.
 */

// ─── Custom Errors ─────────────────────────────────────────────────────────────

error ProductNotFound(bytes32 productId);
error ProductAlreadyRegistered(bytes32 productId);
error ZeroAddress();
error ZeroProductId();

// ─── Structs ───────────────────────────────────────────────────────────────────

struct AdapterInfo {
    address adapterAddress;
    string name;
    bool isXCM;
    bool active;
    uint256 registeredAt; // block.timestamp at registration
}

/// @dev Read-only projection returned by getAllProducts(). Never stored.
///      Frontend decodes this via viem readContract — do not change field order or types
///      without updating the Module 8 useProducts() hook.
///      riskScore is always 0 until Module 4 wires in RiskOracle.
struct ProductView {
    bytes32 productId;
    address adapterAddress;
    string name;
    bool isXCM;
    uint256 apyBps; // from cachedAPY
    uint256 tvlUSD; // from cachedTVL
    uint256 utilizationBps; // from cachedUtilization
    uint256 lastUpdated; // block.timestamp of last pushMetadata call
    uint256 riskScore; // always 0 until Module 4 — placeholder field, do not remove
}

// ─── Events ────────────────────────────────────────────────────────────────────

event AdapterRegistered(bytes32 indexed productId, address indexed adapter, string name, bool isXCM);

event AdapterDeactivated(bytes32 indexed productId);

event MetadataUpdated(bytes32 indexed productId, uint256 apyBps, uint256 tvlUSD);

// ─── Contract ──────────────────────────────────────────────────────────────────

contract ConduitRegistry {
    // ── Ownership ──────────────────────────────────────────────────────────────
    // Inline ownership — no OZ import to keep PVM compilation simple.
    // Owner is fixed at deploy time. Transfer not supported in v1.
    address public owner;

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    // ── Core storage ───────────────────────────────────────────────────────────
    mapping(bytes32 => AdapterInfo) private adapters;
    bytes32[] private productIds; // append-only; deactivation does NOT remove entries

    // ── APY/TVL cache — push model ─────────────────────────────────────────────
    mapping(bytes32 => uint256) public cachedAPY; // apyBps
    mapping(bytes32 => uint256) public cachedTVL; // tvlUSD
    mapping(bytes32 => uint256) public cachedUtilization; // utilizationBps
    mapping(bytes32 => uint256) public lastUpdated; // block.timestamp of last push

    // ── Constructor ────────────────────────────────────────────────────────────

    constructor() {
        owner = msg.sender;
    }

    // ── Write functions ────────────────────────────────────────────────────────

    /// @notice Register a new yield adapter.
    /// @param productId  bytes32 identifier. Convention: keccak256("TOKEN:CHAIN:PROTOCOL").
    /// @param adapter    Address of the deployed adapter contract.
    /// @param name       Human-readable product name (stored on-chain for getAllProducts).
    /// @param xcm        True if this adapter routes via XCM (async two-phase settlement).
    function registerAdapter(bytes32 productId, address adapter, string calldata name, bool xcm) external onlyOwner {
        if (productId == bytes32(0)) revert ZeroProductId();
        if (adapter == address(0)) revert ZeroAddress();
        // Block both active and deactivated re-registration to prevent ID reuse.
        if (adapters[productId].adapterAddress != address(0)) {
            revert ProductAlreadyRegistered(productId);
        }

        adapters[productId] =
            AdapterInfo({adapterAddress: adapter, name: name, isXCM: xcm, active: true, registeredAt: block.timestamp});
        productIds.push(productId);

        emit AdapterRegistered(productId, adapter, name, xcm);
    }

    /// @notice Deactivate a registered adapter. The productId is permanently retired.
    /// @dev Does NOT remove from productIds array — the entry is skipped in getAllProducts().
    function deactivateAdapter(bytes32 productId) external onlyOwner {
        if (adapters[productId].adapterAddress == address(0)) {
            revert ProductNotFound(productId);
        }
        adapters[productId].active = false;
        emit AdapterDeactivated(productId);
    }

    /// @notice Push updated APY/TVL/utilisation data into the registry cache.
    /// @dev Access: owner OR the registered adapter itself.
    ///      Allowing adapter-push makes the demo cleaner (adapters self-report live data)
    ///      and is more architecturally honest. Both paths are trusted in v1.
    function pushMetadata(bytes32 productId, uint256 apyBps, uint256 tvlUSD, uint256 utilizationBps) external {
        AdapterInfo storage info = adapters[productId];
        if (!info.active) revert ProductNotFound(productId);
        // Only owner or the adapter itself may push.
        require(msg.sender == owner || msg.sender == info.adapterAddress, "not owner or adapter");

        cachedAPY[productId] = apyBps;
        cachedTVL[productId] = tvlUSD;
        cachedUtilization[productId] = utilizationBps;
        lastUpdated[productId] = block.timestamp;

        emit MetadataUpdated(productId, apyBps, tvlUSD);
    }

    // ── Read functions ─────────────────────────────────────────────────────────

    /// @notice Retrieve the AdapterInfo for an active product.
    /// @dev Used by ConduitRouter on every deposit() call.
    ///      Reverts with ProductNotFound if the product is unknown or deactivated.
    function getAdapter(bytes32 productId) external view returns (AdapterInfo memory) {
        AdapterInfo storage info = adapters[productId];
        if (!info.active) revert ProductNotFound(productId);
        return info;
    }

    /// @notice Return all active products with their cached metadata.
    /// @dev Pure view — never calls into any adapter. Safe to call on every page load.
    ///      Two-pass loop: first counts active products, then fills the result array.
    ///      At testing scale (2–5 products) both passes are negligible gas.
    function getAllProducts() external view returns (ProductView[] memory) {
        uint256 total = productIds.length;

        // Pass 1 — count active products so we can size the result array.
        uint256 activeCount;
        for (uint256 i = 0; i < total; i++) {
            if (adapters[productIds[i]].active) activeCount++;
        }

        ProductView[] memory result = new ProductView[](activeCount);

        // Pass 2 — fill the result array, skipping inactive entries.
        uint256 idx;
        for (uint256 i = 0; i < total; i++) {
            bytes32 pid = productIds[i];
            AdapterInfo storage info = adapters[pid];
            if (!info.active) continue;

            result[idx] = ProductView({
                productId: pid,
                adapterAddress: info.adapterAddress,
                name: info.name,
                isXCM: info.isXCM,
                apyBps: cachedAPY[pid],
                tvlUSD: cachedTVL[pid],
                utilizationBps: cachedUtilization[pid],
                lastUpdated: lastUpdated[pid],
                riskScore: 0 // TODO(Module 4): wire in RiskOracle.getScore(pid)
            });
            idx++;
        }

        return result;
    }

    /// @notice Total number of registered products, including deactivated ones.
    /// @dev Note: this counts ALL registered productIds, not just active ones.
    ///      Use getAllProducts().length for the active count.
    function getProductCount() external view returns (uint256) {
        return productIds.length;
    }
}
