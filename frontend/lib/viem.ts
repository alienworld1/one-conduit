import { createPublicClient, defineChain, http } from "viem";

export const paseoAssetHub = defineChain({
  id: 420420417,
  name: "Paseo Asset Hub",
  nativeCurrency: { name: "PAS", symbol: "PAS", decimals: 18 },
  rpcUrls: {
    default: {
      http: ["https://eth-rpc-testnet.polkadot.io"],
    },
  },
  blockExplorers: {
    default: {
      name: "Paseo Asset Hub Blockscout",
      url: "https://blockscout-testnet.polkadot.io/",
    },
  },
});

export const publicClient = createPublicClient({
  chain: paseoAssetHub,
  transport: http(),
});
