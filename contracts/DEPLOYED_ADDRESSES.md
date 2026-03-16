# OneConduit — Deployed Addresses

**Network:** Paseo Passet Hub
**Chain ID:** (Paseo Passet Hub testnet)

## Module 2 — ConduitRegistry + IYieldAdapter

| Contract | Address | Deployed At |
|---|---|---|
| `ConduitRegistry` | _pending deployment_ | — |

## Module 3 — LocalLendingAdapter

| Contract | Address | Deployed At |
|---|---|---|
| `LocalLendingAdapter` | _pending_ | — |

## Module 4 — RiskOracle (ink! v6 / Rust)

| Contract | Address | Deployed At |
|---|---|---|
| `RiskOracle` | _pending_ | — |

## Module 5 — ConduitRouter

| Contract | Address | Deployed At |
|---|---|---|
| `ConduitRouter` | _pending_ | — |

## Module 6 — XCMAdapter + EscrowVault + PendingReceiptNFT

| Contract | Address | Deployed At |
|---|---|---|
| `XCMAdapter` | _pending_ | — |
| `EscrowVault` | _pending_ | — |
| `PendingReceiptNFT` | _pending_ | — |

---

## Post-deployment verification commands

```bash
# Verify ConduitRegistry is empty after deploy
cast call <REGISTRY_ADDRESS> "getProductCount()(uint256)" --rpc-url $ETH_RPC_URL

# Register a test adapter
cast send <REGISTRY_ADDRESS> \
  "registerAdapter(bytes32,address,string,bool)" \
  <PRODUCT_ID_BYTES32> <ADAPTER_ADDRESS> "Test Product" false \
  --private-key $PRIVATE_KEY --rpc-url $ETH_RPC_URL

# Push metadata
cast send <REGISTRY_ADDRESS> \
  "pushMetadata(bytes32,uint256,uint256,uint256)" \
  <PRODUCT_ID_BYTES32> 500 1000000 5000 \
  --private-key $PRIVATE_KEY --rpc-url $ETH_RPC_URL

# Read all products
cast call <REGISTRY_ADDRESS> "getAllProducts()" --rpc-url $ETH_RPC_URL
```
