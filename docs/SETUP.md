# 1Conduit - Development Setup

## Network

All contracts are deployed on **Paseo Asset Hub** (Polkadot's smart contract testnet).

| Parameter | Value |
|---|---|
| Chain ID | `420420417` |
| ETH-RPC | `https://testnet-passet-hub-eth-rpc.polkadot.io` |
| WS-RPC | `wss://asset-hub-paseo-rpc.n.dwellir.com` |
| Explorer | `https://blockscout-testnet.polkadot.io` |
| Faucet | `https://faucet.polkadot.io/?parachain=1111` |

Get PAS tokens from the faucet before deploying. Select "Passet Hub: smart contracts"
in the chain dropdown.

## Prerequisites

- **Node.js** 18+
- **pnpm** - `npm install -g pnpm`
- **Rust** nightly - `rustup toolchain install nightly`
- **Foundry** (foundry-polkadot fork, not standard Foundry - see step 3)
- **resolc** - the Revive compiler binary (see step 3)
- A wallet private key with PAS balance on Paseo

## 1. Clone the Repository

```bash
git clone <repo-url>
cd one-conduit
```

## 2. Install Frontend Dependencies

```bash
cd frontend
pnpm install
cd ..
```

## 3. Install Foundry (foundry-polkadot)

1Conduit uses `foundry-polkadot` (Parity's fork of Foundry) compiled with `resolc`
(the Revive compiler). Standard `foundryup` does not work.

**Install foundry-polkadot:**

```bash
# Install from paritytech/foundry-polkadot
# Follow current instructions at: https://github.com/paritytech/foundry-polkadot
```

**Install resolc:**
Download the prebuilt binary from https://github.com/paritytech/revive/releases

```bash
# macOS:
chmod +x resolc-universal-apple-darwin
xattr -rc resolc-universal-apple-darwin
sudo mv resolc-universal-apple-darwin /usr/local/bin/resolc

# Linux:
chmod +x resolc-x86_64-unknown-linux-musl
sudo mv resolc-x86_64-unknown-linux-musl /usr/local/bin/resolc
```

Verify:

```bash
resolc --version
forge --version
```

Note: `foundry-polkadot` replaces standard Foundry at the same binary paths.
If you need standard Foundry for other projects, manage with shell aliases.

## 4. Configure Environment

```bash
cp contracts/.env.example contracts/.env
```

Fill in:

```bash
PRIVATE_KEY=0x...your_private_key...
ETH_RPC_URL=https://testnet-passet-hub-eth-rpc.polkadot.io
```

For the relayer:

```bash
cp scripts/.env.example scripts/.env
```

Fill in all contract addresses from `contracts/DEPLOYED_ADDRESSES.md` and your
`RELAYER_PRIVATE_KEY` (must match `XCMAdapter.relayerAddress()`).

## 5. Run Foundry Tests

```bash
cd contracts
forge test
cd ..
```

## 6. Deploy Contracts

If deploying fresh (not using the existing testnet deployment):

```bash
cd contracts

# Deploy registry
forge script script/DeployRegistry.s.sol --rpc-url $ETH_RPC_URL \
  --private-key $PRIVATE_KEY --broadcast

# Deploy RiskOracle
forge script script/DeployRiskOracle.s.sol --rpc-url $ETH_RPC_URL \
  --private-key $PRIVATE_KEY --broadcast

# Deploy router (requires registry + oracle addresses in .env)
forge script script/DeployRouter.s.sol --rpc-url $ETH_RPC_URL \
  --private-key $PRIVATE_KEY --broadcast

# Deploy escrow vault + receipt NFT
forge script script/DeployEscrow.s.sol --rpc-url $ETH_RPC_URL \
  --private-key $PRIVATE_KEY --broadcast

# Deploy XCM adapter (wires EscrowVault + PendingReceiptNFT)
forge script script/DeployXCMAdapter.s.sol --rpc-url $ETH_RPC_URL \
  --private-key $PRIVATE_KEY --broadcast
```

Update `frontend/lib/contracts.ts` with the new addresses after each deployment.

## 7. Seed On-Chain Data

After deploying, seed risk scores and registry metadata:

```bash
# Seed RiskOracle for both products
cast send $RISK_ORACLE \
  "updateScore(bytes32,uint256,uint256,uint256,uint256)" \
  $LOCAL_PRODUCT_ID 2000 1000000 7000 30 \
  --private-key $PRIVATE_KEY --rpc-url $ETH_RPC_URL

cast send $RISK_ORACLE \
  "updateScore(bytes32,uint256,uint256,uint256,uint256)" \
  $XCM_PRODUCT_ID 800 500000 3000 15 \
  --private-key $PRIVATE_KEY --rpc-url $ETH_RPC_URL

# Push metadata to registry
cast send $LOCAL_ADAPTER "pushMetadata()" \
  --private-key $PRIVATE_KEY --rpc-url $ETH_RPC_URL

cast send $XCM_ADAPTER "pushMetadata()" \
  --private-key $PRIVATE_KEY --rpc-url $ETH_RPC_URL
```

Verify:

```bash
# Should return 2 products with non-zero APY and risk scores
cast call $REGISTRY "getAllProducts()" --rpc-url $ETH_RPC_URL
```

## 8. Run the Frontend

```bash
cd frontend
pnpm dev
```

Open http://localhost:3000 and connect a wallet on chain `420420417`.

## 9. Run the Relayer

```bash
cd scripts
npm install
cp .env.example .env
npx tsx relayer.ts settle <receiptId>
```

## Troubleshooting

**`resolc: command not found`**  
`resolc` is not on your `$PATH`. Add its directory to your shell profile:
`export PATH="$PATH:/path/to/resolc/directory"`

**Deposit reverts with `RiskScoreTooLow(0, N)`**  
The RiskOracle has not been seeded for this product. Run the `updateScore()` seed
commands from Step 7.

**`EscrowVault.adapter()` returns `address(0)`**  
`setAdapter()` was not called after XCMAdapter deployment. Run:
`cast send $ESCROW_VAULT "setAdapter(address)" $XCM_ADAPTER --private-key $PK --rpc-url $ETH_RPC_URL`
