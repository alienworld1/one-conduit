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

## Module 4.5 — RiskOracle.sol (Solidity, replaces ink! version)

| Contract | Address | Notes |
|---|---|---|
| `RiskOracle.sol` | 0x925287C7F2BC699A7874FE66Aacc95da432094B3 | Active |
| `RiskOracle` (ink! v6) | 0x6Bee0885A5d7c621215AD773a8c692a1bD16Aa60 | Deprecated — ink! v6 unreliable on Paseo |
| `ConduitRouter` (v2) | 0xc72Eb468E1e406D02A4Cb47aA3BDB69b9F4B6538 | Points at Solidity oracle |
| `ConduitRouter` (v1) | _deprecated_ | Deprecated |

## Module 5 — EscrowVault + PendingReceiptNFT

| Contract | Address | Deployed At |
|---|---|---|
| `EscrowVault` | 0xe68C52f6bd8985e321d1C81491608EA0af63C577 | — |
| `PendingReceiptNFT` | 0x31D4BbD8FFB9c77B90F5b679D19C998ACdDC14AF | — |

> **Note:** EscrowVault and PendingReceiptNFT share the same address in the table above
> because both were deployed in the same Module 5 script run. Fill in the correct addresses
> from the broadcast output once confirmed on Blockscout.

## Module 6 — XCMAdapter + ConduitRouter v3

ConduitRegistry (v2):     0x7a32F47C190BCa3eDC20683e138d90E91f2cb82B
EscrowVault (v2):         0xA1bcADa3388f1A89CdAa15182E3A56B6FDD1975f
PendingReceiptNFT (v2):   0x1376f5e8338ca0962FE59CC28d0824E2F44E84e5
XCMAdapter (v2):          0x91bfFE24DCAE154D9aE26374AA4C8c460192d4e0
ConduitRouter (v3, new):  0x1F6525b86EF8E32513Eb5F15528b553297ee3643
RiskOracle (unchanged):   0x925287C7F2BC699A7874FE66Aacc95da432094B3
MockDOT (deployed):       0x6C242AdFF547877Ad6719b4785b45E7238d28D94
LocalLendingAdapter (unchanged): 0x5b50eaE5Fd7b3e09687938FA9D69ccc6a9200746

XCM ProductId:
0xdd8f8d3075abdebf7d685b0ccf77a86310e9926882318d1daa27caa9dca971c9
XCM template keccak256:
0xf74fb7eab26e94efd316c23ecd1e52cf07c56ffd42ae37a2ec91f5e6b3d4e20f

### Key Transactions — XCM Phase 1

| Action | Tx Hash |
|---|---|
| Phase 1 deposit (Demo Scene 3) | _pending_ |
| XCM precompile internal call visible at `0x00000000000000000000000000000000000a0000` | *(see deposit tx trace in Blockscout)* |

### Module 7 Prerequisite Verification (Receipt NFT)

| Check | Result |
|---|---|
| `cast call 0x1376f5e8338ca0962FE59CC28d0824E2F44E84e5 "markSettled(uint256)" 1` | reverted with `0x82b42900` (`Unauthorized`) |

This confirms `markSettled(uint256)` exists on the deployed receipt NFT and is adapter-protected.

---

## Post-deployment verification commands

```bash
# Verify ConduitRegistry product count (should be 2 after Module 6)
cast call $REGISTRY_ADDRESS "getProductCount()(uint256)" --rpc-url $ETH_RPC_URL

# Verify EscrowVault.adapter() == XCMAdapter (NOT address(0))
cast call $ESCROW_VAULT_ADDRESS "adapter()(address)" --rpc-url $ETH_RPC_URL

# Verify PendingReceiptNFT.adapter() == XCMAdapter (NOT address(0))
cast call $RECEIPT_NFT_ADDRESS "adapter()(address)" --rpc-url $ETH_RPC_URL

# Read all registered products (should return local + XCM)
cast call $REGISTRY_ADDRESS "getAllProducts()" --rpc-url $ETH_RPC_URL

# Check escrow balance after Phase 1 deposit (receipt ID 1)
cast call $ESCROW_VAULT_ADDRESS "getBalance(uint256)(uint256)" 1 --rpc-url $ETH_RPC_URL

# Check NFT owner after Phase 1 deposit
cast call $RECEIPT_NFT_ADDRESS "ownerOf(uint256)(address)" 1 --rpc-url $ETH_RPC_URL

# Check NFT metadata
cast call $RECEIPT_NFT_ADDRESS \
  "receipts(uint256)(bytes32,uint256,address,uint256,bool)" 1 \
  --rpc-url $ETH_RPC_URL

# Check XCMAdapter view functions
cast call $XCM_ADAPTER_ADDRESS "getAPY()(uint256)" --rpc-url $ETH_RPC_URL     # → 800
cast call $XCM_ADAPTER_ADDRESS "isXCM()(bool)" --rpc-url $ETH_RPC_URL         # → true
cast call $XCM_ADAPTER_ADDRESS "getTVL()(uint256)" --rpc-url $ETH_RPC_URL     # → 0

# Verify ConduitRouter v3 has receiptNFT set
cast call $CONDUIT_ROUTER_V3_ADDRESS "receiptNFT()(address)" --rpc-url $ETH_RPC_URL

# Attempt settle() — should revert NotImplemented (proves delegation to XCMAdapter)
cast send $CONDUIT_ROUTER_V3_ADDRESS "settle(uint256,bytes)" 1 0x \
  --private-key $PRIVATE_KEY --rpc-url $ETH_RPC_URL
```

## Testnet notes

- **No real XCM cross-chain routing exists on Paseo.** The `xcmExecute` call runs locally on Passet Hub — the XCM precompile at `0x00000000000000000000000000000000000a0000` is real and visible in the transaction trace. On mainnet, the same instruction set routes to Bifrost for vDOT minting.
- **Fixed 1 DOT template.** The `xcmMessageTemplate` encodes exactly 10,000,000,000 planck regardless of the deposited amount. The actual deposited amount is escrowed correctly. This mismatch is a testnet limitation (SCALE `Compact<u128>` encoding is variable-length). See `XCMAdapter.sol` file-level comment.
- **MockDOT stand-in.** The `underlyingToken` is a MockERC20 — not native PAS or bridged DOT. The XCM `WithdrawAsset` instruction references `{ parents: 0, interior: Here }` (local native asset = PAS). The "DOT demo" vs "PAS native" mismatch is a testnet limitation, disclosed in demo narration.
- **EscrowVault.adapter() is a one-time setter.** Once set, it cannot be changed. If the XCMAdapter needs to be redeployed, the EscrowVault must also be redeployed.
