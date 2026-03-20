export const routerAbi = [
  {
    name: 'receiptNFT',
    type: 'function',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ type: 'address' }]
  },
  {
    name: 'registry',
    type: 'function',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ type: 'address' }]
  },
  {
    name: 'settle',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'receiptId', type: 'uint256' },
      { name: 'proof', type: 'bytes' }
    ],
    outputs: []
  },
  {
    name: 'NotConfigured',
    type: 'error',
    inputs: []
  },
  {
    name: 'NotImplemented',
    type: 'error',
    inputs: []
  },
  {
    name: 'ReceiptNotFound',
    type: 'error',
    inputs: [{ name: 'receiptId', type: 'uint256' }]
  },
  {
    name: 'ReceiptAlreadySettled',
    type: 'error',
    inputs: [{ name: 'receiptId', type: 'uint256' }]
  },
  {
    name: 'InvalidSettlementProof',
    type: 'error',
    inputs: [{ name: 'receiptId', type: 'uint256' }]
  }
] as const

export const receiptNFTAbi = [
  {
    name: 'isSettled',
    type: 'function',
    stateMutability: 'view',
    inputs: [{ name: 'tokenId', type: 'uint256' }],
    outputs: [{ type: 'bool' }]
  },
  {
    name: 'ownerOf',
    type: 'function',
    stateMutability: 'view',
    inputs: [{ name: 'tokenId', type: 'uint256' }],
    outputs: [{ type: 'address' }]
  },
  {
    name: 'receipts',
    type: 'function',
    stateMutability: 'view',
    inputs: [{ name: 'tokenId', type: 'uint256' }],
    outputs: [
      { name: 'productId', type: 'bytes32' },
      { name: 'amount', type: 'uint256' },
      { name: 'originalDepositor', type: 'address' },
      { name: 'dispatchBlock', type: 'uint256' },
      { name: 'settled', type: 'bool' }
    ]
  }
] as const

export const xcmAdapterAbi = [
  {
    name: 'relayerAddress',
    type: 'function',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ type: 'address' }]
  },
  {
    name: 'XCMDispatched',
    type: 'event',
    inputs: [
      { name: 'user', type: 'address', indexed: true },
      { name: 'productId', type: 'bytes32', indexed: true },
      { name: 'amount', type: 'uint256', indexed: false },
      { name: 'receiptId', type: 'uint256', indexed: false },
      { name: 'xcmMsgHash', type: 'bytes32', indexed: false }
    ]
  }
] as const

export const registryAbi = [
  {
    name: 'getAdapter',
    type: 'function',
    stateMutability: 'view',
    inputs: [{ name: 'productId', type: 'bytes32' }],
    outputs: [
      {
        type: 'tuple',
        components: [
          { name: 'adapterAddress', type: 'address' },
          { name: 'name', type: 'string' },
          { name: 'isXCM', type: 'bool' },
          { name: 'active', type: 'bool' },
          { name: 'registeredAt', type: 'uint256' }
        ]
      }
    ]
  },
  {
    name: 'ProductNotFound',
    type: 'error',
    inputs: [{ name: 'productId', type: 'bytes32' }]
  }
] as const
