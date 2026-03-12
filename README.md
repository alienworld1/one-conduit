# OneConduit

Cross-protocol yield aggregator native to Polkadot Hub.

---

## What It Does

OneConduit lets users and AI agents discover yield-bearing positions across local Polkadot Hub protocols and XCM-connected parachains via a single deposit interface.

1. **Rust/ink! + Solidity in the same system.** `RiskOracle.rs` is an ink! v6 contract called from `ConduitRouter.sol` via a cross-VM call. PVM is the only production smart contract VM where this is possible.
2. **XCM as a first-class primitive.** The two-phase deposit model makes async XCM a product feature — in-flight positions are represented as tradeable ERC-721 receipt NFTs.
3. **DOT flows natively.** No wrapping. No bridging.

---

## Repository Structure

```
contracts/     Solidity contracts (Foundry + Revive → PVM)
ink/           Rust/ink! contracts (cargo-contract → PVM)
scripts/       Relayer / agent tooling (Module 7 — TODO)
frontend/      Next.js interface (Module 8+ — TODO)
docs/          Setup guide, agent guide
```

---

## Setup

See [docs/SETUP.md](docs/SETUP.md) for the full environment setup guide including toolchain installation, network configuration, and deployment instructions.

**Quick prerequisite check:**
```bash
resolc --version          # 1.0.0
forge --version           # foundry-polkadot nightly
cargo contract --version  # 6.x.x
```

---

## Deployed Addresses

See [contracts/DEPLOYED_ADDRESSES.md](contracts/DEPLOYED_ADDRESSES.md).

---

*OneConduit — cold infrastructure, warm data*
