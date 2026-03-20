export const ADDRESSES = {
  conduitRegistry: "0x2B29eDEdfbe33581673755d217Da600f92eA7CC6",
  conduitRouter: "0x212349691746d378DC814AF70674474843F695BD",
  riskOracle: "0x925287C7F2BC699A7874FE66Aacc95da432094B3",
  escrowVault: "0x19EA950c5468D8b2Da584F777124AC3a017d0cA5",
  pendingReceiptNFT: "0x2B6b31eF4e39565BDd1a914fA70B8451812F7210",
  xcmAdapter: "0xF605c8B148A6Af6B6ABC049074fBFaa653219F46",
  localAdapter: "0x5b50eaE5Fd7b3e09687938FA9D69ccc6a9200746",
  mockDOT: "0x629FA1da2eafa71456F72e0A8dA208D25A9D6bd2",
  mockUSDC: "0x5FAfa9c09BC5d6b79fF0e3dBC0AaaB651eEB894C",
} as const;

export const TOKEN_META = {
  mUSDC: {
    symbol: "mUSDC",
    address: ADDRESSES.mockUSDC,
    decimals: 6,
  },
  mockDOT: {
    symbol: "MockDOT",
    address: ADDRESSES.mockDOT,
    // Deployed MockDOT on Paseo currently exposes 6 decimals.
    // Keep frontend encoding aligned with on-chain token units.
    decimals: 6,
  },
  cYLD: {
    symbol: "cYLD",
    decimals: 6,
  },
} as const;

export const LOCAL_PRODUCT_ID =
  "0x28f9cb741def117848906060ecc245d99a3b4e1b9afa666c115411a988c0de91" as const;

export const XCM_PRODUCT_ID =
  "0xdd8f8d3075abdebf7d685b0ccf77a86310e9926882318d1daa27caa9dca971c9" as const;

export const registryAbi = [
  {
    type: "function",
    stateMutability: "view",
    name: "getAllProducts",
    inputs: [],
    outputs: [
      {
        type: "tuple[]",
        components: [
          { name: "productId", type: "bytes32" },
          { name: "adapterAddress", type: "address" },
          { name: "name", type: "string" },
          { name: "isXCM", type: "bool" },
          { name: "apyBps", type: "uint256" },
          { name: "tvlUSD", type: "uint256" },
          { name: "utilizationBps", type: "uint256" },
          { name: "lastUpdated", type: "uint256" },
          { name: "riskScore", type: "uint256" },
        ],
      },
    ],
  },
] as const;

export const riskOracleAbi = [
  {
    type: "function",
    stateMutability: "view",
    name: "getScore",
    inputs: [{ name: "productId", type: "bytes32" }],
    outputs: [{ type: "uint256" }],
  },
  {
    type: "function",
    stateMutability: "view",
    name: "getScoreInputs",
    inputs: [{ name: "productId", type: "uint256" }],
    outputs: [
      {
        type: "tuple",
        components: [
          { name: "apyBps", type: "uint256" },
          { name: "tvlUSD", type: "uint256" },
          { name: "utilizationBps", type: "uint256" },
          { name: "contractAgeDays", type: "uint256" },
        ],
      },
    ],
  },
] as const;

export const routerAbi = [
  {
    type: "function",
    stateMutability: "nonpayable",
    name: "deposit",
    inputs: [
      { name: "productId", type: "bytes32" },
      { name: "amount", type: "uint256" },
      { name: "minRiskScore", type: "uint256" },
    ],
    outputs: [],
  },
  {
    type: "function",
    stateMutability: "nonpayable",
    name: "settle",
    inputs: [
      { name: "receiptId", type: "uint256" },
      { name: "proof", type: "bytes" },
    ],
    outputs: [],
  },
  {
    type: "function",
    stateMutability: "view",
    name: "getQuote",
    inputs: [
      { name: "productId", type: "bytes32" },
      { name: "amount", type: "uint256" },
    ],
    outputs: [{ type: "uint256" }],
  },
  {
    type: "event",
    name: "Deposited",
    inputs: [
      { indexed: true, name: "user", type: "address" },
      { indexed: true, name: "productId", type: "bytes32" },
      { indexed: false, name: "amountIn", type: "uint256" },
      { indexed: false, name: "tokensOut", type: "uint256" },
    ],
    anonymous: false,
  },
  {
    type: "event",
    name: "XCMDispatched",
    inputs: [
      { indexed: true, name: "user", type: "address" },
      { indexed: true, name: "productId", type: "bytes32" },
      { indexed: false, name: "amount", type: "uint256" },
      { indexed: false, name: "receiptId", type: "uint256" },
      { indexed: false, name: "xcmMsgHash", type: "bytes32" },
    ],
    anonymous: false,
  },
] as const;

export const erc20Abi = [
  {
    type: "function",
    stateMutability: "nonpayable",
    name: "approve",
    inputs: [
      { name: "spender", type: "address" },
      { name: "value", type: "uint256" },
    ],
    outputs: [{ type: "bool" }],
  },
  {
    type: "function",
    stateMutability: "view",
    name: "allowance",
    inputs: [
      { name: "owner", type: "address" },
      { name: "spender", type: "address" },
    ],
    outputs: [{ type: "uint256" }],
  },
  {
    type: "function",
    stateMutability: "view",
    name: "balanceOf",
    inputs: [{ name: "account", type: "address" }],
    outputs: [{ type: "uint256" }],
  },
] as const;

export const receiptNFTAbi = [
  {
    type: "function",
    stateMutability: "view",
    name: "ownerOf",
    inputs: [{ name: "tokenId", type: "uint256" }],
    outputs: [{ type: "address" }],
  },
  {
    type: "function",
    stateMutability: "view",
    name: "isSettled",
    inputs: [{ name: "tokenId", type: "uint256" }],
    outputs: [{ type: "bool" }],
  },
  {
    type: "function",
    stateMutability: "view",
    name: "receipts",
    inputs: [{ name: "tokenId", type: "uint256" }],
    outputs: [
      {
        type: "tuple",
        components: [
          { name: "productId", type: "bytes32" },
          { name: "amount", type: "uint256" },
          { name: "originalDepositor", type: "address" },
          { name: "dispatchBlock", type: "uint256" },
          { name: "settled", type: "bool" },
        ],
      },
    ],
  },
  {
    type: "function",
    stateMutability: "view",
    name: "nextTokenId",
    inputs: [],
    outputs: [{ type: "uint256" }],
  },
  {
    type: "function",
    stateMutability: "nonpayable",
    name: "transferFrom",
    inputs: [
      { name: "from", type: "address" },
      { name: "to", type: "address" },
      { name: "tokenId", type: "uint256" },
    ],
    outputs: [],
  },
  {
    type: "event",
    name: "ReceiptMinted",
    inputs: [
      { indexed: true, name: "tokenId", type: "uint256" },
      { indexed: true, name: "to", type: "address" },
      { indexed: true, name: "productId", type: "bytes32" },
      { indexed: false, name: "amount", type: "uint256" },
    ],
    anonymous: false,
  },
  {
    type: "event",
    name: "ReceiptSettled",
    inputs: [
      { indexed: true, name: "tokenId", type: "uint256" },
      { indexed: true, name: "finalHolder", type: "address" },
    ],
    anonymous: false,
  },
  {
    type: "event",
    name: "Transfer",
    inputs: [
      { indexed: true, name: "from", type: "address" },
      { indexed: true, name: "to", type: "address" },
      { indexed: true, name: "tokenId", type: "uint256" },
    ],
    anonymous: false,
  },
] as const;
