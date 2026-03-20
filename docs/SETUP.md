# OneConduit — Environment Setup

> **Author:** Module 0 scaffold  
> **Last updated:** March 2026  
> **Purpose:** Reproduce the exact build environment. If you hit a step that differs from this doc, update it.

---

## Prerequisites

- Linux or macOS (x86_64 or arm64)
- Git, curl, wget
- A Paseo Passet Hub wallet with PAS tokens ([faucet](https://paritytech.github.io/polkadot-testnet-faucet/))

---

## Network Details — Paseo Passet Hub

| Parameter | Value |
|---|---|
| Chain ID | `420420417` |
| ETH-RPC | `https://eth-rpc-testnet.polkadot.io/` |
| Block explorer | `https://blockscout-testnet.polkadot.io` |
| Faucet | `https://faucet.polkadot.io/` |
| Native token | `PAS` |
| Existential deposit | `5000 PAS` |

---

## Installation Order

Install in **this exact order**. Some tools conflict if installed out of order.

### 1. Rust Toolchain

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
rustup toolchain install nightly
rustup target add riscv32imac-unknown-none-elf --toolchain nightly
```

The `ink/rust-toolchain.toml` file in this repo pins the `ink/` workspace to nightly automatically. You do not need to set the default globally.

### 2. solc v0.8.28

`resolc` (the Revive compiler) shells out to `solc` internally. You need `solc` 0.8.28 on `$PATH`.

```bash
# Option A — solc-select (recommended, manages multiple versions)
pip install solc-select
solc-select install 0.8.28
solc-select use 0.8.28

# Option B — direct binary (Linux x86_64)
wget https://github.com/ethereum/solidity/releases/download/v0.8.28/solc-static-linux \
  -O /usr/local/bin/solc
chmod +x /usr/local/bin/solc
```

Verify: `solc --version` should print `0.8.28+...`

### 3. resolc v1.0.0 (Revive compiler)

Download the prebuilt binary. **Do not build from source** — it requires a custom LLVM build and takes hours.

```bash
# Linux x86_64
wget https://github.com/paritytech/revive/releases/download/v1.0.0/resolc-x86_64-unknown-linux-musl \
  -O /usr/local/bin/resolc
chmod +x /usr/local/bin/resolc

# macOS universal
wget https://github.com/paritytech/revive/releases/download/v1.0.0/resolc-universal-apple-darwin \
  -O /usr/local/bin/resolc
chmod +x /usr/local/bin/resolc
# macOS ONLY — remove Gatekeeper quarantine flag
xattr -rc /usr/local/bin/resolc
```

Verify: `resolc --version` should print `1.0.0` without error.

**Critical:** `resolc` must be on `$PATH`. `foundry-polkadot` with `resolc_compile = true` shells out to it; the error message if it's missing is cryptic ("compiler not found"), not "resolc not found".

### 4. foundry-polkadot (Nightly Build)

This replaces standard Foundry if you have it installed. They share the same binary paths. That's fine — this project requires the Polkadot fork everywhere.

```bash
curl -L https://raw.githubusercontent.com/paritytech/foundry-polkadot/main/foundryup/install | bash
foundryup
```

> ⚠ **Use the nightly build**. The stable release does not recognise the `polkadot-testnet` chain name.

Verify: `forge --version` should include `foundry-polkadot` or `nightly` in the output.

### 5. cargo-contract v6

v5 does not support ink! v6 Solidity ABI mode. Must be v6+.

```bash
cargo install cargo-contract --version "^6" --locked
```

Verify: `cargo contract --version` should print `cargo-contract 6.x.x`.

### 6. (Optional) ink-node for local testing

```bash
cargo install contracts-node --git https://github.com/paritytech/substrate-contracts-node.git
```

Not required for Module 0 — we deploy directly to Paseo.

---

## Repository Layout (after Module 0)

```
oneconduit/
├── contracts/           # Solidity + Foundry (resolc → PVM)
│   ├── src/             # HelloPVM.sol, HelloCaller.sol → later: ConduitRouter, etc.
│   ├── test/            # Forge unit tests (run on Anvil/EVM; logic-only)
│   ├── script/          # Forge deploy scripts
│   ├── lib/             # forge install dependencies
│   ├── foundry.toml
│   └── DEPLOYED_ADDRESSES.md
├── ink/                 # Rust / ink! workspace (cargo-contract → PVM)
│   ├── hello-ink/       # Module 0 throwaway; validates cross-VM path
│   ├── risk-oracle/     # Module 1 — RiskOracle.rs lives here (TODO)
│   ├── Cargo.toml       # Workspace root
│   └── rust-toolchain.toml
├── scripts/             # Relayer script (Module 7) — TODO
├── frontend/            # Next.js app (Module 8+) — TODO
├── docs/
│   ├── SETUP.md         # This file
│   └── agent-guide.md   # Module 11 — TODO
├── .env                 # gitignored — see .env.example below
└── README.md
```

---

## Environment Variables

Create `.env` at the project root. It is `.gitignore`'d.

```bash
# .env
PRIVATE_KEY=0x...          # deployer wallet private key (hex, with 0x prefix)
ETH_RPC_URL=https://eth-rpc-testnet.polkadot.io/
```

Load before running any `forge` or `cast` command:
```bash
source .env
```

---

## Deploying HelloPVM (Solidity → PVM)

```bash
cd contracts

# Install forge-std dependency
forge install foundry-rs/forge-std --no-commit

# Build with Revive (resolc must be on $PATH)
forge build --resolc

# Deploy
forge script script/DeployHelloPVM.s.sol \
  --broadcast \
  --rpc-url $ETH_RPC_URL \
  --private-key $PRIVATE_KEY \
  --resolc

# Verify the deploy
# Replace <HELLO_PVM_ADDRESS> with the address printed by the script
cast call <HELLO_PVM_ADDRESS> "getNumber(uint256)" 7 \
  --rpc-url $ETH_RPC_URL
# Expected output: 8 (input + 1)
```

Record the address in `contracts/DEPLOYED_ADDRESSES.md`.

---

## Deploying HelloInk (Rust/ink! → PVM)

```bash
cd ink/hello-ink

# ink! unit tests (runs locally, no node required)
cargo test

# Build the contract (outputs .contract, .wasm, .json in target/ink/)
cargo contract build --release

# Deploy to Paseo Passet Hub
# --suri is your private key in substrate SR25519 format (or use --suri "//Alice" for dev)
cargo contract instantiate \
  --constructor new \
  --suri "$PRIVATE_KEY" \
  --url wss://rpc.ibp.network/paseo \
  --args \
  target/ink/hello_ink.contract

# The command prints the deployed contract address. Record it.
# Verify:
cargo contract call \
  --contract <HELLO_INK_ADDRESS> \
  --message get_number \
  --suri "$PRIVATE_KEY" \
  --url wss://rpc.ibp.network/paseo
# Expected output: 42
```

> ⚠ **Note:** `cargo contract instantiate` connects via WebSocket Substrate RPC (`wss://`), not the ETH-RPC endpoint. These are different protocols for the same chain. The contract is accessible from both sides after deployment.

Record the `AccountId` (Substrate address) and the ETH-compatible `H160` address in `contracts/DEPLOYED_ADDRESSES.md`. You need the H160 form for `HelloCaller`'s constructor.

---

## Deploying HelloCaller + Cross-VM Validation

This is the **hard exit criterion** for Module 0. If `callInk()` returns 42, the cross-VM path is proven and Module 1 is unblocked.

```bash
cd contracts

# Set the HelloInk H160 address (from the step above)
export HELLO_INK_ADDRESS=0x...

forge script script/DeployHelloCaller.s.sol \
  --broadcast \
  --rpc-url $ETH_RPC_URL \
  --private-key $PRIVATE_KEY \
  --resolc

# Validate the cross-VM call
cast call <HELLO_CALLER_ADDRESS> "callInk()" \
  --rpc-url $ETH_RPC_URL
# Expected output: 42 (as a uint256)
```

Record the transaction hash in `contracts/DEPLOYED_ADDRESSES.md` under "Cross-VM validation tx".

---

## Known Gotchas

### `resolc` not on `$PATH`
When `resolc_compile = true` but `resolc` is missing from `$PATH`, the error is "compiler binary not found" not "resolc not found". Check with `which resolc` first.

### macOS Gatekeeper blocks `resolc`
Run `xattr -rc /usr/local/bin/resolc` to strip the quarantine attribute. Without this, macOS silently refuses to execute the binary.

### `forge test` always runs on Anvil (EVM), never on PVM
This is correct behaviour. Unit tests for logic live in `contracts/test/` and run against the EVM Anvil fork. PVM-specific behaviour (actual contract execution) must be tested on Paseo. Don't try to run `forge test` against Paseo — it won't work.

### PAS existential deposit
Your deployer account needs to stay above 0.01 PAS after paying gas. The faucet dispenses ~5000 PAS — plenty. If your balance drops to 0 the account is reaped and contracts become unreachable.

### `uint128` vs `uint256` at the ink! boundary
`get_number()` in HelloInk returns `u128` → `uint128` in Solidity ABI. `HelloCaller.sol` casts to `uint256` safely. In Module 1, `RiskOracle.rs` will use `ink::U256` → `uint256` for clean alignment. Don't conflate the two.

### ink! deploy uses Substrate RPC, not ETH-RPC
`cargo contract instantiate` uses `--url wss://...` (Substrate WebSocket), not the ETH-RPC endpoint. This is expected. The contract is usable from Solidity via its H160 address once deployed.

### foundry-polkadot nightly vs stable
The `polkadot-testnet` named chain is only recognised in the nightly build. If `forge` says "unknown chain", you have the stable build. Re-run `foundryup` (it pulls nightly by default for foundry-polkadot).

---

## Verification Checklist

- [ ] `resolc --version` → `1.0.0`
- [ ] `forge --version` → foundry-polkadot nightly
- [ ] `cargo contract --version` → `6.x.x`
- [ ] `cast chain-id --rpc-url https://eth-rpc-testnet.polkadot.io/` → `420420417`
- [ ] Deployer wallet has PAS balance on [blockscout-testnet.polkadot.io](https://blockscout-testnet.polkadot.io)
- [ ] `forge build --resolc` in `contracts/` succeeds
- [ ] `HelloPVM` deployed — address in `DEPLOYED_ADDRESSES.md`
- [ ] `cast call <HelloPVM> "getNumber(uint256)" 7` → `8`
- [ ] `cargo contract build` in `ink/hello-ink/` succeeds
- [ ] `HelloInk` deployed — address in `DEPLOYED_ADDRESSES.md`
- [ ] `HelloInk.get_number()` → `42`
- [ ] `HelloCaller` deployed — address in `DEPLOYED_ADDRESSES.md`
- [ ] `cast call <HelloCaller> "callInk()"` → `42` ← **Module 0 exit criterion**
- [ ] Cross-VM tx hash in `DEPLOYED_ADDRESSES.md` under "Cross-VM validation tx"
