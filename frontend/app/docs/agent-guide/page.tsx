import { CodeBlock } from "@/components/CodeBlock";

const codeDiscover = `import { createPublicClient, defineChain, http } from "viem"

const paseoAssetHub = defineChain({
  id: 420420417,
  name: "Paseo Asset Hub",
  nativeCurrency: { name: "PAS", symbol: "PAS", decimals: 18 },
  rpcUrls: {
    default: { http: ["https://eth-rpc-testnet.polkadot.io/"] },
  },
})

const client = createPublicClient({
  chain: paseoAssetHub,
  transport: http(),
})

const products = await client.readContract({
  address: "0x7a32F47C190BCa3eDC20683e138d90E91f2cb82B",
  abi: [{
    name: "getAllProducts",
    type: "function",
    stateMutability: "view",
    inputs: [],
    outputs: [{
      type: "tuple[]",
      components: [
        { name: "productId",      type: "bytes32" },
        { name: "adapterAddress", type: "address" },
        { name: "name",           type: "string" },
        { name: "isXCM",          type: "bool" },
        { name: "apyBps",         type: "uint256" },
        { name: "tvlUSD",         type: "uint256" },
        { name: "utilizationBps", type: "uint256" },
        { name: "lastUpdated",    type: "uint256" },
        { name: "riskScore",      type: "uint256" },
      ],
    }],
  }],
  functionName: "getAllProducts",
})

// products[0].apyBps -> e.g. 2000n (= 20% APY)
// products[0].riskScore -> e.g. 62n (out of 100)
// products[0].isXCM -> false (local) or true (XCM path)`;

const codeRisk = `// productId is bytes32 from getAllProducts
// cast to uint256 for RiskOracle calls
const productIdAsUint = BigInt("0x...productId...")

const score = await client.readContract({
  address: "0x925287C7F2BC699A7874FE66Aacc95da432094B3",
  abi: [{
    name: "getScore",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "productId", type: "uint256" }],
    outputs: [{ type: "uint256" }],
  }],
  functionName: "getScore",
  args: [productIdAsUint],
})
// score -> 62n

const inputs = await client.readContract({
  address: "0x925287C7F2BC699A7874FE66Aacc95da432094B3",
  abi: [{
    name: "getScoreInputs",
    type: "function",
    stateMutability: "view",
    inputs: [{ name: "productId", type: "uint256" }],
    outputs: [{
      type: "tuple",
      components: [
        { name: "apyBps",          type: "uint256" },
        { name: "tvlUSD",          type: "uint256" },
        { name: "utilizationBps",  type: "uint256" },
        { name: "contractAgeDays", type: "uint256" },
        { name: "updatedAt",       type: "uint256" },
      ],
    }],
  }],
  functionName: "getScoreInputs",
  args: [productIdAsUint],
})
// inputs.apyBps -> 2000n, inputs.tvlUSD -> 1000000n, etc.`;

const codeRiskFormula = `Score formula (0-100):
utilisation component * 40% + TVL component * 35% + maturity * 15% + APY sanity * 10%
Score of 0 = unscored. Treat as non-depositable.
Score < minRiskScore in deposit() -> reverts RiskScoreTooLow.`;

const codeLocalDeposit = `import { createWalletClient, custom, http } from "viem"
import { privateKeyToAccount } from "viem/accounts"

const walletClient = createWalletClient({
  account: "0xYourAddress",
  chain: paseoAssetHub,
  transport: custom(window.ethereum),
})

// For headless agents:
const agentAccount = privateKeyToAccount("0xYourPrivateKey")
const agentWalletClient = createWalletClient({
  account: agentAccount,
  chain: paseoAssetHub,
  transport: http(),
})

const ROUTER = "0x1F6525b86EF8E32513Eb5F15528b553297ee3643"
const MUSDC = "0x5FAfa9c09BC5d6b79fF0e3dBC0AaaB651eEB894C"
const LOCAL_PRODUCT_ID = "0x28f9cb741def117848906060ecc245d99a3b4e1b9afa666c115411a988c0de91"

const amount = 100_000_000n // 100 mUSDC (6 decimals)
const minRiskScore = 50n

await walletClient.writeContract({
  address: MUSDC,
  abi: [{
    name: "approve",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [
      { name: "spender", type: "address" },
      { name: "amount", type: "uint256" },
    ],
    outputs: [{ type: "bool" }],
  }],
  functionName: "approve",
  args: [ROUTER, amount],
})

const txHash = await walletClient.writeContract({
  address: ROUTER,
  abi: [{
    name: "deposit",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [
      { name: "productId", type: "bytes32" },
      { name: "amount", type: "uint256" },
      { name: "minRiskScore", type: "uint256" },
    ],
    outputs: [],
  }],
  functionName: "deposit",
  args: [LOCAL_PRODUCT_ID, amount, minRiskScore],
})

const receipt = await client.waitForTransactionReceipt({ hash: txHash })
// receipt.logs contains Deposited event with tokensOut`;

const codeXcmDeposit = `const MOCK_DOT = "0x6C242AdFF547877Ad6719b4785b45E7238d28D94"
const XCM_PRODUCT = "0xdd8f8d3075abdebf7d685b0ccf77a86310e9926882318d1daa27caa9dca971c9"

const dotAmount = 1_000_000_000_000n

await walletClient.writeContract({
  address: MOCK_DOT,
  abi: [{
    name: "approve",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [
      { name: "spender", type: "address" },
      { name: "amount", type: "uint256" },
    ],
    outputs: [{ type: "bool" }],
  }],
  functionName: "approve",
  args: [ROUTER, dotAmount],
})

const xcmTxHash = await walletClient.writeContract({
  address: ROUTER,
  abi: [{
    name: "deposit",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [
      { name: "productId", type: "bytes32" },
      { name: "amount", type: "uint256" },
      { name: "minRiskScore", type: "uint256" },
    ],
    outputs: [],
  }],
  functionName: "deposit",
  args: [XCM_PRODUCT, dotAmount, 40n],
})

const xcmReceipt = await client.waitForTransactionReceipt({ hash: xcmTxHash })
// Parse XCMDispatched from xcmReceipt.logs to get receiptId`;

const codeXcmNote = `Testnet note: XCM executes locally on Paseo Asset Hub (no active cross-chain channel).
The XCM precompile at 0x00000000000000000000000000000000000a0000 is called and visible in traces.
On mainnet, this routes to Bifrost for vDOT minting.
Escrowed amount and PendingReceiptNFT mint are fully functional on testnet.`;

const codeSettleMonitor = `const RECEIPT_NFT = "0x1376f5e8338ca0962FE59CC28d0824E2F44E84e5"

const logs = await client.getLogs({
  address: RECEIPT_NFT,
  event: {
    name: "Transfer",
    type: "event",
    inputs: [
      { name: "from", type: "address", indexed: true },
      { name: "to", type: "address", indexed: true },
      { name: "tokenId", type: "uint256", indexed: true },
    ],
  },
  args: { to: "0xAgentAddress" },
  fromBlock: 0n,
})

const tokenIds = logs.map((l) => l.args.tokenId)

for (const tokenId of tokenIds) {
  const settled = await client.readContract({
    address: RECEIPT_NFT,
    abi: [{
      name: "isSettled",
      type: "function",
      stateMutability: "view",
      inputs: [{ name: "tokenId", type: "uint256" }],
      outputs: [{ type: "bool" }],
    }],
    functionName: "isSettled",
    args: [tokenId],
  })

  console.log(\`Receipt #\${tokenId}: \${settled ? "settled" : "pending"}\`)
}`;

const codeRelayer = `cd scripts && npm install

cp .env.example .env
# Fill in: ETH_RPC_URL, RELAYER_PRIVATE_KEY, contract addresses

npx tsx scripts/relayer.ts settle <receiptId>
npx tsx scripts/relayer.ts monitor
npx tsx scripts/relayer.ts status <receiptId>`;

const codeDirectSettle = `import { encodePacked, keccak256 } from "viem"

const ROUTER = "0x1F6525b86EF8E32513Eb5F15528b553297ee3643"
const XCM_ADAPTER = "0x91bfFE24DCAE154D9aE26374AA4C8c460192d4e0"
const receiptId = 1n

const chainId = await client.getChainId()
const messageHash = keccak256(encodePacked(
  ["string", "uint256", "address", "uint256"],
  ["OneConduit:settle:", BigInt(chainId), XCM_ADAPTER, receiptId]
))

const proof = await relayerWalletClient.signMessage({
  message: { raw: messageHash },
})

await walletClient.writeContract({
  address: ROUTER,
  abi: [{
    name: "settle",
    type: "function",
    stateMutability: "nonpayable",
    inputs: [
      { name: "receiptId", type: "uint256" },
      { name: "proof", type: "bytes" },
    ],
    outputs: [],
  }],
  functionName: "settle",
  args: [receiptId, proof],
})`;

export default function AgentGuidePage() {
  return (
    <div className="mx-auto w-full max-w-7xl px-4 py-16 md:px-6">
      <div className="max-w-170">
        <article className="leading-[1.8] text-text-secondary">
          <h1 className="font-display text-[28px] font-medium text-text-primary">Agent Guide</h1>
          <p className="mb-6 mt-3 text-[14px]">
            1Conduit is fully programmable via smart contract calls. No UI or off-chain API required.
          </p>

          <p className="text-[11px] tracking-widest text-text-muted uppercase">Section 1</p>
          <h2 className="mb-6 border-b border-border pb-3 pt-10 font-display text-[18px] font-medium text-text-primary">
            Overview
          </h2>
          <p className="mb-4 text-[14px]">
            1Conduit is a yield aggregator on Polkadot Hub. It exposes a single router contract that
            accepts deposits into any registered yield product - Hub-native lending pools and
            XCM-dispatched parachain positions - with on-chain risk scoring.
          </p>
          <p className="mb-4 text-[14px]">
            All agent operations use the ETH-RPC endpoint at{" "}
            <span className="font-data text-[13px] text-accent">
              https://eth-rpc-testnet.polkadot.io/
            </span>{" "}
            (Chain ID: <span className="font-data text-[13px] text-accent">420420417</span>).
          </p>
          <p className="mb-4 text-[14px]">
            No off-chain API. No SDK required. Any EVM-compatible library (viem, ethers, web3.py)
            works.
          </p>

          <p className="text-[11px] tracking-widest text-text-muted uppercase">Section 2</p>
          <h2 className="mb-6 border-b border-border pb-3 pt-10 font-display text-[18px] font-medium text-text-primary">
            Contract Addresses
          </h2>
          <div className="mb-6 overflow-x-auto border border-border bg-surface">
            <table className="w-full border-collapse">
              <thead>
                <tr className="border-b border-border">
                  <th className="px-4 py-2 text-left text-[11px] tracking-widest text-text-muted uppercase">
                    Contract
                  </th>
                  <th className="px-4 py-2 text-left text-[11px] tracking-widest text-text-muted uppercase">
                    Address
                  </th>
                </tr>
              </thead>
              <tbody className="font-data text-[13px] text-text-primary">
                <tr className="border-b border-border-subtle"><td className="px-4 py-2">ConduitRouter</td><td className="px-4 py-2">0x1F6525b86EF8E32513Eb5F15528b553297ee3643</td></tr>
                <tr className="border-b border-border-subtle"><td className="px-4 py-2">ConduitRegistry</td><td className="px-4 py-2">0x7a32F47C190BCa3eDC20683e138d90E91f2cb82B</td></tr>
                <tr className="border-b border-border-subtle"><td className="px-4 py-2">RiskOracle</td><td className="px-4 py-2">0x925287C7F2BC699A7874FE66Aacc95da432094B3</td></tr>
                <tr className="border-b border-border-subtle"><td className="px-4 py-2">PendingReceiptNFT</td><td className="px-4 py-2">0x1376f5e8338ca0962FE59CC28d0824E2F44E84e5</td></tr>
                <tr className="border-b border-border-subtle"><td className="px-4 py-2">EscrowVault</td><td className="px-4 py-2">0xA1bcADa3388f1A89CdAa15182E3A56B6FDD1975f</td></tr>
                <tr className="border-b border-border-subtle"><td className="px-4 py-2">XCMAdapter</td><td className="px-4 py-2">0x91bfFE24DCAE154D9aE26374AA4C8c460192d4e0</td></tr>
                <tr className="border-b border-border-subtle"><td className="px-4 py-2">XCMAdapter Relayer</td><td className="px-4 py-2">0x6Bee0885A5d7c621215AD773a8c692a1bD16Aa60</td></tr>
                <tr className="border-b border-border-subtle"><td className="px-4 py-2">LocalLendingAdapter</td><td className="px-4 py-2">0x5b50eaE5Fd7b3e09687938FA9D69ccc6a9200746</td></tr>
                <tr className="border-b border-border-subtle"><td className="px-4 py-2">MockDOT</td><td className="px-4 py-2">0x6C242AdFF547877Ad6719b4785b45E7238d28D94</td></tr>
                <tr><td className="px-4 py-2">MockUSDC (mUSDC)</td><td className="px-4 py-2">0x5FAfa9c09BC5d6b79fF0e3dBC0AaaB651eEB894C</td></tr>
              </tbody>
            </table>
          </div>
          <p className="mb-2 text-[14px]">Product IDs:</p>
          <ul className="mb-4 ml-4 list-none text-[14px]">
            <li className='mb-2 before:mr-2 before:text-text-muted before:content-["-"]'>
              Local (USDC lending):{" "}
              <span className="font-data text-[13px] text-accent">
                0x28f9cb741def117848906060ecc245d99a3b4e1b9afa666c115411a988c0de91
              </span>
            </li>
            <li className='mb-2 before:mr-2 before:text-text-muted before:content-["-"]'>
              XCM (DOT / Bifrost):{" "}
              <span className="font-data text-[13px] text-accent">
                0xdd8f8d3075abdebf7d685b0ccf77a86310e9926882318d1daa27caa9dca971c9
              </span>
            </li>
          </ul>

          <p className="text-[11px] tracking-widest text-text-muted uppercase">Step 1</p>
          <h2 className="mb-6 border-b border-border pb-3 pt-10 font-display text-[18px] font-medium text-text-primary">
            Discover Yield Products
          </h2>
          <CodeBlock code={codeDiscover} language="typescript" filename="discover-products.ts" />

          <p className="text-[11px] tracking-widest text-text-muted uppercase">Step 2</p>
          <h2 className="mb-6 border-b border-border pb-3 pt-10 font-display text-[18px] font-medium text-text-primary">
            Check On-Chain Risk Score
          </h2>
          <CodeBlock code={codeRisk} language="typescript" filename="risk-score.ts" />
          <CodeBlock code={codeRiskFormula} language="bash" filename="score-formula.txt" />

          <p className="text-[11px] tracking-widest text-text-muted uppercase">Step 3</p>
          <h2 className="mb-6 border-b border-border pb-3 pt-10 font-display text-[18px] font-medium text-text-primary">
            Execute a Local Deposit
          </h2>
          <CodeBlock code={codeLocalDeposit} language="typescript" filename="local-deposit.ts" />

          <p className="text-[11px] tracking-widest text-text-muted uppercase">Step 4</p>
          <h2 className="mb-6 border-b border-border pb-3 pt-10 font-display text-[18px] font-medium text-text-primary">
            Execute an XCM Deposit
          </h2>
          <CodeBlock code={codeXcmDeposit} language="typescript" filename="xcm-deposit.ts" />
          <CodeBlock code={codeXcmNote} language="bash" filename="xcm-testnet-note.txt" />

          <p className="text-[11px] tracking-widest text-text-muted uppercase">Step 5</p>
          <h2 className="mb-6 border-b border-border pb-3 pt-10 font-display text-[18px] font-medium text-text-primary">
            Monitor and Settle a Receipt
          </h2>
          <CodeBlock code={codeSettleMonitor} language="typescript" filename="monitor-receipts.ts" />
          <CodeBlock code={codeRelayer} language="bash" filename="relayer-commands.sh" />
          <CodeBlock code={codeDirectSettle} language="typescript" filename="direct-settle.ts" />

          <p className="text-[11px] tracking-widest text-text-muted uppercase">Section 8</p>
          <h2 className="mb-6 border-b border-border pb-3 pt-10 font-display text-[18px] font-medium text-text-primary">
            Testnet Limitations
          </h2>
          <ul className="mb-4 ml-4 list-none text-[14px]">
            <li className='mb-2 before:mr-2 before:text-text-muted before:content-["-"]'>
              MockDOT and MockUSDC are stand-in ERC-20 tokens. Mint via
              <span className="ml-1 font-data text-[13px] text-accent">MockERC20.mint()</span>.
            </li>
            <li className='mb-2 before:mr-2 before:text-text-muted before:content-["-"]'>
              XCM executes locally on Paseo Asset Hub (no parachain destination available on
              testnet).
            </li>
            <li className='mb-2 before:mr-2 before:text-text-muted before:content-["-"]'>
              The XCM message template encodes a fixed 1 DOT amount regardless of deposited
              amount. Escrowed funds still match the actual deposit.
            </li>
            <li className='mb-2 before:mr-2 before:text-text-muted before:content-["-"]'>
              Risk scores are seeded manually by the oracle owner via
              <span className="ml-1 font-data text-[13px] text-accent">updateScore()</span>.
            </li>
            <li className='mb-2 before:mr-2 before:text-text-muted before:content-["-"]'>
              Settlement requires the relayer key. For testnet usage, contact the deployer.
            </li>
          </ul>
        </article>
      </div>
    </div>
  );
}
