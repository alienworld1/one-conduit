# OneConduit — Deployed Addresses

**Network:** Paseo Asset Hub
**Chain ID:** (Paseo Asset Hub testnet)

## Module 2 — ConduitRegistry + IYieldAdapter

| Contract | Address | Deployed At |
|---|---|---|
| `ConduitRegistry` | 0xa5E8c0Bf7b2caf0F9A779D1B32640DC88AC258A2 | 0x6cfab407fbf90ec287ce63afd4a70e9027a1ee27b986bcf895e68c4eba554ada |

## Module 3 — LocalLendingAdapter + MockLendingPool

| Contract | Address | Deployed At |
|---|---|---|
| `MockERC20` (mUSDC — canonical USDC stand-in) | 0x5FAfa9c09BC5d6b79fF0e3dBC0AaaB651eEB894C | — |
| `MockYieldToken` (cYLD — deployed by MockLendingPool) | 0x256Ca433e024Ed7baB26a1fE6aC0658636C2749B | — |
| `MockLendingPool` | 0x430819D80517A1Dbe98b47cF70FC951163Ceed5b | — |
| `LocalLendingAdapter` | 0x5b50eaE5Fd7b3e09687938FA9D69ccc6a9200746 | — |

## Module 4 — RiskOracle (ink! v6 / Rust)

| Contract | Address | Deployed At |
|---|---|---|
| `RiskOracle` (v1 — broken, as_u128 panic) | 0xDfB3c383642960D1488aBcf7107f053455A96f82 | — |
| `RiskOracle` (v2 — fixed, low_u128) | 0x925287C7F2BC699A7874FE66Aacc95da432094B3 | — |

## Module 5 — ConduitRouter

| Contract | Address | Deployed At |
|---|---|---|
| `ConduitRouter` | _pending_ | — |

## Module 4.5 — RiskOracle.sol (Solidity, replaces ink! version)

| Contract | Address | Notes |
|---|---|---|
| `RiskOracle.sol` | 0x925287C7F2BC699A7874FE66Aacc95da432094B3 | Active |
| `RiskOracle` (ink! v6) | 0x6Bee0885A5d7c621215AD773a8c692a1bD16Aa60 | Deprecated — ink! v6 unreliable on Paseo |
| `ConduitRouter` (v2) | 0xc72Eb468E1e406D02A4Cb47aA3BDB69b9F4B6538 | Points at Solidity oracle |
| `ConduitRouter` (v1) | _pending_ | Deprecated |

## Module 6 — XCMAdapter + EscrowVault + PendingReceiptNFT

| Contract | Address | Deployed At |
|---|---|---|
| `XCMAdapter` | _pending_ | — |
| `EscrowVault` | 0xe68C52f6bd8985e321d1C81491608EA0af63C577 | — |
| `PendingReceiptNFT` | 0xe68C52f6bd8985e321d1C81491608EA0af63C577 | — |

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
