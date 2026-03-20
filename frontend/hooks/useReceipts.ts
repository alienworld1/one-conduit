"use client";

import { useEffect, useMemo, useState } from "react";
import type { Address } from "viem";
import { parseAbiItem } from "viem";
import { ADDRESSES, receiptNFTAbi } from "@/lib/contracts";
import { publicClient } from "@/lib/viem";

const transferEvent = parseAbiItem(
  "event Transfer(address indexed from, address indexed to, uint256 indexed tokenId)",
);

type ReceiptTuple = {
  productId: `0x${string}`;
  amount: bigint;
  originalDepositor: Address;
  dispatchBlock: bigint;
  settled: boolean;
};

export type Receipt = {
  tokenId: bigint;
  productId: `0x${string}`;
  amount: bigint;
  originalDepositor: Address;
  dispatchBlock: bigint;
  settled: boolean;
  currentOwner: Address | null;
  wasSentByConnectedUser: boolean;
};

function sortReceipts(a: Receipt, b: Receipt): number {
  if (a.settled !== b.settled) {
    return a.settled ? 1 : -1;
  }

  if (a.dispatchBlock !== b.dispatchBlock) {
    return a.dispatchBlock > b.dispatchBlock ? -1 : 1;
  }

  if (a.tokenId === b.tokenId) {
    return 0;
  }

  return a.tokenId > b.tokenId ? -1 : 1;
}

export function useReceipts(address: Address | null) {
  const [receipts, setReceipts] = useState<Receipt[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [refreshTick, setRefreshTick] = useState(0);

  const normalizedAddress = useMemo(() => address?.toLowerCase(), [address]);

  useEffect(() => {
    if (!address) {
      setReceipts([]);
      setLoading(false);
      setError(null);
      return;
    }

    let cancelled = false;

    async function loadReceipts() {
      setLoading(true);
      setError(null);

      try {
        const nftAddress = ADDRESSES.pendingReceiptNFT;

        // Paseo RPC rejects some topic arrays with trailing null indexed filters.
        // Query all Transfer logs for this contract, then filter by address client-side.
        const transferLogs = await publicClient.getLogs({
          address: nftAddress,
          event: transferEvent,
          fromBlock: BigInt(0),
        });

        const receivedIds = new Set<bigint>();
        const sentIds = new Set<bigint>();

        for (const log of transferLogs) {
          const tokenId = log.args.tokenId;
          const from = log.args.from?.toLowerCase();
          const to = log.args.to?.toLowerCase();

          if (typeof tokenId !== "bigint" || !normalizedAddress) {
            continue;
          }

          if (to === normalizedAddress) {
            receivedIds.add(tokenId);
          }

          if (from === normalizedAddress) {
            sentIds.add(tokenId);
          }
        }

        const tokenIds = Array.from(receivedIds);

        if (tokenIds.length === 0) {
          if (!cancelled) {
            setReceipts([]);
          }
          return;
        }

        const entries = await Promise.all(
          tokenIds.map(async (tokenId) => {
            const [receiptData, settled, owner] = await Promise.all([
              publicClient.readContract({
                address: nftAddress,
                abi: receiptNFTAbi,
                functionName: "receipts",
                args: [tokenId],
              }) as Promise<ReceiptTuple>,
              publicClient.readContract({
                address: nftAddress,
                abi: receiptNFTAbi,
                functionName: "isSettled",
                args: [tokenId],
              }) as Promise<boolean>,
              publicClient
                .readContract({
                  address: nftAddress,
                  abi: receiptNFTAbi,
                  functionName: "ownerOf",
                  args: [tokenId],
                })
                .then((result) => result as Address)
                .catch(() => null),
            ]);

            return {
              tokenId,
              productId: receiptData.productId,
              amount: receiptData.amount,
              originalDepositor: receiptData.originalDepositor,
              dispatchBlock: receiptData.dispatchBlock,
              settled,
              currentOwner: owner,
              wasSentByConnectedUser: sentIds.has(tokenId),
            } satisfies Receipt;
          }),
        );

        if (!cancelled) {
          setReceipts(entries.sort(sortReceipts));
        }
      } catch (err) {
        if (!cancelled) {
          const message = err instanceof Error ? err.message : "Failed to load receipts";
          setError(message);
        }
      } finally {
        if (!cancelled) {
          setLoading(false);
        }
      }
    }

    loadReceipts();

    return () => {
      cancelled = true;
    };
  }, [address, normalizedAddress, refreshTick]);

  function refetch() {
    setRefreshTick((prev) => prev + 1);
  }

  return { receipts, loading, error, refetch };
}
