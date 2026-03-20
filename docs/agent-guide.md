# OneConduit - AI Agent Guide

## Overview

OneConduit is fully programmable via smart contract calls. No UI or centralized API is required.
The full flow for agents is:

1. Discover products from `ConduitRegistry`.
2. Deposit via `ConduitRouter.deposit(...)`.
3. Track pending receipt NFTs.
4. Settle via `ConduitRouter.settle(receiptId, proof)` using a relayer-signed proof.

## Contract Addresses (Paseo Passet Hub)

| Contract | Address |
|---|---|
| ConduitRegistry (v2) | `0x2B29eDEdfbe33581673755d217Da600f92eA7CC6` |
| ConduitRouter (v3) | `0x212349691746d378DC814AF70674474843F695BD` |
| RiskOracle (Solidity) | `0x925287C7F2BC699A7874FE66Aacc95da432094B3` |
| XCMAdapter (v2) | `0xF605c8B148A6Af6B6ABC049074fBFaa653219F46` |
| EscrowVault (v2) | `0x19EA950c5468D8b2Da584F777124AC3a017d0cA5` |
| PendingReceiptNFT (v2) | `0x2B6b31eF4e39565BDd1a914fA70B8451812F7210` |
| MockDOT | `0x629FA1da2eafa71456F72e0A8dA208D25A9D6bd2` |

XCM product ID (DOT -> Bifrost vDOT v1):
`0xdd8f8d3075abdebf7d685b0ccf77a86310e9926882318d1daa27caa9dca971c9`

## Step 1: Discover Yield Products

```ts
import { createPublicClient, http } from 'viem'

const client = createPublicClient({ transport: http(process.env.ETH_RPC_URL!) })

const products = await client.readContract({
  address: '0x2B29eDEdfbe33581673755d217Da600f92eA7CC6',
  abi: [{
    name: 'getAllProducts',
    type: 'function',
    stateMutability: 'view',
    inputs: [],
    outputs: [{
      type: 'tuple[]',
      components: [
        { name: 'productId', type: 'bytes32' },
        { name: 'name', type: 'string' },
        { name: 'adapterAddress', type: 'address' },
        { name: 'underlyingToken', type: 'address' },
        { name: 'isXCM', type: 'bool' },
        { name: 'active', type: 'bool' },
        { name: 'apyBps', type: 'uint256' },
        { name: 'tvlUSD', type: 'uint256' },
        { name: 'utilizationBps', type: 'uint256' }
      ]
    }]
  }],
  functionName: 'getAllProducts'
})
```

## Step 2: Execute a Local Deposit

```ts
await walletClient.writeContract({
  address: '0x212349691746d378DC814AF70674474843F695BD',
  abi: [{
    name: 'deposit',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'productId', type: 'bytes32' },
      { name: 'amount', type: 'uint256' },
      { name: 'minRiskScore', type: 'uint256' }
    ],
    outputs: []
  }],
  functionName: 'deposit',
  args: [LOCAL_PRODUCT_ID, 1_000_000n, 60n]
})
```

## Step 3: Execute an XCM Deposit

```ts
await walletClient.writeContract({
  address: '0x212349691746d378DC814AF70674474843F695BD',
  abi: routerAbi,
  functionName: 'deposit',
  args: [
    '0xdd8f8d3075abdebf7d685b0ccf77a86310e9926882318d1daa27caa9dca971c9',
    1_000_000_000_000n,
    40n
  ]
})
```

Success outcome for XCM path:

1. Escrow is locked in `EscrowVault`.
2. XCM precompile call is attempted (visible in trace at `0x...0a0000`).
3. A `PendingReceiptNFT` is minted to the user.

## Step 4: Monitor Pending Receipts

Use the provided relayer script status mode:

```bash
npx tsx scripts/relayer.ts status 1
```

Or read directly:

```ts
const receipt = await publicClient.readContract({
  address: '0x2B6b31eF4e39565BDd1a914fA70B8451812F7210',
  abi: receiptNFTAbi,
  functionName: 'receipts',
  args: [1n]
})
```

## Step 5: Settle a Receipt

Module 7 settlement uses an EIP-191 relayer signature over:

`keccak256(abi.encodePacked("OneConduit:settle:", chainId, xcmAdapterAddress, receiptId))`

The easiest path is using the relayer script:

```bash
npx tsx scripts/relayer.ts settle 1
```

This signs proof bytes and calls `ConduitRouter.settle(receiptId, proof)`.

## Running the Relayer

1. Copy env file:

```bash
cp scripts/.env.example scripts/.env
```

1. Install dependencies in `scripts`:

```bash
cd scripts && npm install
```

1. Run one of the three modes:

```bash
npx tsx scripts/relayer.ts monitor
npx tsx scripts/relayer.ts settle 1
npx tsx scripts/relayer.ts status 1
```

Notes:

1. `RELAYER_PRIVATE_KEY` must match `XCMAdapter.relayerAddress`.
2. `SETTLEMENT_DELAY_BLOCKS=0` is best for demo flow.

## Testnet Notes

1. Paseo currently has no live cross-parachain route for this demo path. The precompile call is still real and visible in tx trace.
2. The current XCM template is fixed to 1 DOT in the encoded message bytes; escrowed amount tracking remains correct on-chain.
3. `MockDOT` is used as the input token stand-in on testnet.
