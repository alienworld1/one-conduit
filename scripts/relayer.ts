import { config as loadDotenv } from 'dotenv'
import { existsSync } from 'node:fs'
import { resolve } from 'node:path'

import {
  BaseError,
  createPublicClient,
  createWalletClient,
  encodePacked,
  getAddress,
  Hex,
  http,
  keccak256
} from 'viem'
import { privateKeyToAccount } from 'viem/accounts'

import { receiptNFTAbi, registryAbi, routerAbi, xcmAdapterAbi } from './abis'

type Env = {
  ETH_RPC_URL: string
  RELAYER_PRIVATE_KEY: Hex
  CONDUIT_ROUTER_ADDRESS: `0x${string}`
  RECEIPT_NFT_ADDRESS: `0x${string}`
  XCM_ADAPTER_ADDRESS: `0x${string}`
  SETTLEMENT_DELAY_BLOCKS: number
}

const scriptDir = __dirname
const repoRoot = resolve(scriptDir, '..')

function loadEnvFiles(): string[] {
  const candidates = [
    resolve(process.cwd(), '.env.local'),
    resolve(process.cwd(), '.env'),
    resolve(scriptDir, '.env.local'),
    resolve(scriptDir, '.env'),
    resolve(repoRoot, '.env.local'),
    resolve(repoRoot, '.env')
  ]

  const uniqueCandidates = [...new Set(candidates)]
  const loaded: string[] = []

  for (const filePath of uniqueCandidates) {
    if (!existsSync(filePath)) continue
    loadDotenv({ path: filePath, override: false })
    loaded.push(filePath)
  }

  return loaded
}

function requiredEnv(name: string, loadedEnvFiles: string[]): string {
  const value = process.env[name]
  if (!value || value.trim().length === 0) {
    const checkedFiles = loadedEnvFiles.length > 0 ? loadedEnvFiles.join(', ') : '(no .env files found)'
    throw new Error(
      `Missing environment variable: ${name}. ` +
        `Set it in your terminal or add it to a .env file. Checked: ${checkedFiles}`
    )
  }
  return value.trim()
}

function loadEnv(): Env {
  const loadedEnvFiles = loadEnvFiles()
  const delayRaw = process.env.SETTLEMENT_DELAY_BLOCKS?.trim() ?? '0'
  const delay = Number(delayRaw)

  if (!Number.isInteger(delay) || delay < 0) {
    throw new Error(
      `SETTLEMENT_DELAY_BLOCKS must be a non-negative integer, received: ${delayRaw}`
    )
  }

  return {
    ETH_RPC_URL: requiredEnv('ETH_RPC_URL', loadedEnvFiles),
    RELAYER_PRIVATE_KEY: requiredEnv('RELAYER_PRIVATE_KEY', loadedEnvFiles) as Hex,
    CONDUIT_ROUTER_ADDRESS: getAddress(requiredEnv('CONDUIT_ROUTER_ADDRESS', loadedEnvFiles)),
    RECEIPT_NFT_ADDRESS: getAddress(requiredEnv('RECEIPT_NFT_ADDRESS', loadedEnvFiles)),
    XCM_ADAPTER_ADDRESS: getAddress(requiredEnv('XCM_ADAPTER_ADDRESS', loadedEnvFiles)),
    SETTLEMENT_DELAY_BLOCKS: delay
  }
}

const env = loadEnv()
const relayerAccount = privateKeyToAccount(env.RELAYER_PRIVATE_KEY)

const publicClient = createPublicClient({
  transport: http(env.ETH_RPC_URL)
})

const walletClient = createWalletClient({
  account: relayerAccount,
  transport: http(env.ETH_RPC_URL),
  chain: undefined
})

type SettleRoute = {
  routerReceiptNFT: `0x${string}`
  registry: `0x${string}`
  productId: `0x${string}`
  routedAdapter: `0x${string}`
  routedAdapterName: string
  configuredRelayer: `0x${string}` | null
}

async function getSettleRoute(receiptId: bigint): Promise<SettleRoute> {
  const [routerReceiptNFT, registry] = await Promise.all([
    publicClient.readContract({
      address: env.CONDUIT_ROUTER_ADDRESS,
      abi: routerAbi,
      functionName: 'receiptNFT'
    }),
    publicClient.readContract({
      address: env.CONDUIT_ROUTER_ADDRESS,
      abi: routerAbi,
      functionName: 'registry'
    })
  ])

  if (getAddress(routerReceiptNFT) !== env.RECEIPT_NFT_ADDRESS) {
    throw new Error(
      `Router receiptNFT mismatch. Router uses ${routerReceiptNFT}, env has ${env.RECEIPT_NFT_ADDRESS}. ` +
        'Update CONDUIT_ROUTER_ADDRESS / RECEIPT_NFT_ADDRESS to matching deployment.'
    )
  }

  const metadata = await publicClient.readContract({
    address: env.RECEIPT_NFT_ADDRESS,
    abi: receiptNFTAbi,
    functionName: 'receipts',
    args: [receiptId]
  })

  const productId = metadata[0] as `0x${string}`
  const adapterInfo = await publicClient.readContract({
    address: registry,
    abi: registryAbi,
    functionName: 'getAdapter',
    args: [productId]
  })

  const routedAdapter = getAddress(adapterInfo.adapterAddress)
  let configuredRelayer: `0x${string}` | null = null

  try {
    configuredRelayer = getAddress(
      await publicClient.readContract({
        address: routedAdapter,
        abi: xcmAdapterAbi,
        functionName: 'relayerAddress'
      })
    )
  } catch {
    configuredRelayer = null
  }

  return {
    routerReceiptNFT: getAddress(routerReceiptNFT),
    registry: getAddress(registry),
    productId,
    routedAdapter,
    routedAdapterName: adapterInfo.name,
    configuredRelayer
  }
}

function normalizeMessage(error: unknown): string {
  if (error instanceof BaseError) {
    return error.shortMessage || error.message
  }
  if (error instanceof Error) {
    return error.message
  }
  return String(error)
}

async function waitForBlock(targetBlock: bigint): Promise<void> {
  while (true) {
    const current = await publicClient.getBlockNumber()
    if (current >= targetBlock) return
    await new Promise((resolve) => setTimeout(resolve, 3000))
  }
}

async function settleReceipt(receiptId: bigint): Promise<void> {
  console.log(`\nSettling receipt #${receiptId}...`)

  const route = await getSettleRoute(receiptId)
  console.log(`Resolved product: ${route.productId}`)
  console.log(`Router adapter:   ${route.routedAdapter} (${route.routedAdapterName})`)

  if (route.routedAdapter !== env.XCM_ADAPTER_ADDRESS) {
    throw new Error(
      `XCM_ADAPTER_ADDRESS mismatch. Router resolves ${route.routedAdapter}, env has ${env.XCM_ADAPTER_ADDRESS}. ` +
        'Update XCM_ADAPTER_ADDRESS in your env to the routed adapter.'
    )
  }

  if (route.configuredRelayer != null) {
    console.log(`Adapter relayer:  ${route.configuredRelayer}`)
    console.log(`Signer address:   ${relayerAccount.address}`)

    if (route.configuredRelayer !== relayerAccount.address) {
      throw new Error(
        `RELAYER_PRIVATE_KEY mismatch. Adapter expects ${route.configuredRelayer}, ` +
          `but current key signs as ${relayerAccount.address}.`
      )
    }
  }

  const isSettled = await publicClient.readContract({
    address: env.RECEIPT_NFT_ADDRESS,
    abi: receiptNFTAbi,
    functionName: 'isSettled',
    args: [receiptId]
  })

  if (isSettled) {
    console.log(`Receipt #${receiptId} is already settled.`)
    return
  }

  const currentHolder = await publicClient.readContract({
    address: env.RECEIPT_NFT_ADDRESS,
    abi: receiptNFTAbi,
    functionName: 'ownerOf',
    args: [receiptId]
  })
  console.log(`Current holder: ${currentHolder}`)

  const chainId = await publicClient.getChainId()
  const messageHash = keccak256(
    encodePacked(
      ['string', 'uint256', 'address', 'uint256'],
      ['OneConduit:settle:', BigInt(chainId), env.XCM_ADAPTER_ADDRESS, receiptId]
    )
  )

  // viem applies EIP-191 personal-sign prefix to raw hash bytes, matching Solidity verify logic.
  const signature = await walletClient.signMessage({
    account: relayerAccount,
    message: { raw: messageHash }
  })
  console.log(`Proof: ${signature}`)

  try {
    await publicClient.simulateContract({
      account: relayerAccount.address,
      address: env.CONDUIT_ROUTER_ADDRESS,
      abi: routerAbi,
      functionName: 'settle',
      args: [receiptId, signature]
    })
  } catch (err: unknown) {
    const message = normalizeMessage(err)
    if (message.includes('NotImplemented')) {
      throw new Error(
        'Settlement path is still stubbed on-chain (NotImplemented). ' +
          `Router resolved adapter ${route.routedAdapter}. ` +
          'Deploy Module 7 contracts (or the updated XCMAdapter with settle implementation) and update registry/router wiring.'
      )
    }

    throw new Error(`Settlement simulation failed before send: ${message}`)
  }

  const txHash = await walletClient.writeContract({
    address: env.CONDUIT_ROUTER_ADDRESS,
    abi: routerAbi,
    functionName: 'settle',
    args: [receiptId, signature],
    chain: undefined
  })
  console.log(`Transaction submitted: ${txHash}`)

  const receipt = await publicClient.waitForTransactionReceipt({ hash: txHash })
  console.log(`Confirmed in block ${receipt.blockNumber}`)
  console.log(`Gas used: ${receipt.gasUsed}`)

  const settled = await publicClient.readContract({
    address: env.RECEIPT_NFT_ADDRESS,
    abi: receiptNFTAbi,
    functionName: 'isSettled',
    args: [receiptId]
  })
  console.log(`On-chain settled: ${settled}`)
  console.log(`Funds released to: ${currentHolder}`)
}

async function status(receiptId: bigint): Promise<void> {
  const [owner, isSettled, metadata] = await Promise.all([
    publicClient
      .readContract({
        address: env.RECEIPT_NFT_ADDRESS,
        abi: receiptNFTAbi,
        functionName: 'ownerOf',
        args: [receiptId]
      })
      .catch(() => 'BURNED' as const),
    publicClient.readContract({
      address: env.RECEIPT_NFT_ADDRESS,
      abi: receiptNFTAbi,
      functionName: 'isSettled',
      args: [receiptId]
    }),
    publicClient.readContract({
      address: env.RECEIPT_NFT_ADDRESS,
      abi: receiptNFTAbi,
      functionName: 'receipts',
      args: [receiptId]
    })
  ])

  console.log(`\nReceipt #${receiptId}`)
  console.log(`Status:   ${isSettled ? 'SETTLED' : 'PENDING'}`)
  console.log(`Holder:   ${owner}`)
  console.log(`Amount:   ${metadata[1]} planck`)
  console.log(`Product:  ${metadata[0]}`)
  console.log(`Dispatch block: ${metadata[3]}`)
}

async function monitor(): Promise<void> {
  console.log('OneConduit Relayer - monitoring XCMDispatched events...')
  console.log(`XCMAdapter: ${env.XCM_ADAPTER_ADDRESS}`)
  console.log(`Settlement delay: ${env.SETTLEMENT_DELAY_BLOCKS} blocks\n`)

  const unwatch = publicClient.watchContractEvent({
    address: env.XCM_ADAPTER_ADDRESS,
    abi: xcmAdapterAbi,
    eventName: 'XCMDispatched',
    onLogs: async (logs) => {
      for (const log of logs) {
        const receiptId = log.args.receiptId
        const user = log.args.user
        if (receiptId == null) continue

        console.log(`XCMDispatched: receiptId=${receiptId}, user=${user}`)

        if (env.SETTLEMENT_DELAY_BLOCKS > 0 && log.blockNumber != null) {
          const target = log.blockNumber + BigInt(env.SETTLEMENT_DELAY_BLOCKS)
          console.log(`Waiting until block ${target}...`)
          await waitForBlock(target)
        }

        await settleReceipt(receiptId).catch((err: unknown) => {
          const message = err instanceof Error ? err.message : String(err)
          console.error(`Failed to settle #${receiptId}: ${message}`)
        })
      }
    },
    onError: (err) => {
      console.error(`Watch error: ${err.message}`)
    },
    poll: true,
    pollingInterval: 4000
  })

  process.on('SIGINT', () => {
    unwatch()
    process.exit(0)
  })

  await new Promise(() => {})
}

function usage(): never {
  console.error('Usage: npx tsx scripts/relayer.ts <monitor|settle|status> [receiptId]')
  process.exit(1)
  // eslint-disable-next-line no-unreachable
  throw new Error('unreachable')
}

async function main(): Promise<void> {
  const mode = process.argv[2]

  if (!mode) usage()

  if (mode === 'monitor') {
    await monitor()
    return
  }

  if (mode === 'settle') {
    const raw = process.argv[3]
    if (!raw) usage()
    await settleReceipt(BigInt(raw))
    return
  }

  if (mode === 'status') {
    const raw = process.argv[3]
    if (!raw) usage()
    await status(BigInt(raw))
    return
  }

  usage()
}

main().catch((err: unknown) => {
  const message = err instanceof Error ? err.stack ?? err.message : normalizeMessage(err)
  console.error(message)
  process.exit(1)
})
