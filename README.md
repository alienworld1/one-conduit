# OneConduit

Cross-protocol yield aggregator native to Polkadot Hub.

---

## What It Does

OneConduit lets users and AI agents discover yield-bearing positions across local Polkadot Hub protocols and XCM-connected parachains via a single deposit interface.

1. **Risk-gated routing in Solidity.** `ConduitRouter.sol` enforces a minimum risk score from on-chain `RiskOracle.sol` before deposits are forwarded.
2. **XCM as a first-class primitive.** The two-phase deposit model makes async XCM a product feature — in-flight positions are represented as tradeable ERC-721 receipt NFTs.
3. **DOT flows natively.** No wrapping. No bridging.

---

## Architecture Notes

The original RiskOracle was implemented in Rust using ink! v6. During development, ink! v6 proved unreliable on Paseo Passet Hub following its discontinuation in January 2026. The community successor (wrevive) launched March 3, 2026 and is explicitly not production-ready. Rather than introduce an unstable dependency two days before submission, we ported RiskOracle to Solidity — the scoring formula is unchanged.

The PVM-experiments story is carried by the full stack: every contract in OneConduit — registry, router, adapters, and XCM dispatch — runs on PolkaVM's RISC-V execution environment. The sharpest Polkadot-native demonstration remains Module 6: a Solidity contract calling the XCM precompile to dispatch cross-chain messages to a parachain in a single transaction. This primitive does not exist on Ethereum.

---

## Repository Structure

```text
contracts/     Solidity contracts (Foundry + Revive → PVM)
ink/           Rust contracts (cargo-contract → PVM)
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
