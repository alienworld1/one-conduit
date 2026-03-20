"use client";

import { useEffect, useState } from "react";
import { ADDRESSES, routerAbi } from "@/lib/contracts";
import { publicClient } from "@/lib/viem";

export function useQuote(productId: `0x${string}`, amountRaw: bigint, fallbackQuote?: bigint) {
  const [quote, setQuote] = useState<bigint | null>(null);

  useEffect(() => {
    if (!productId || amountRaw === BigInt(0)) {
      return;
    }

    const timer = setTimeout(async () => {
      try {
        const estimate = await publicClient.readContract({
          address: ADDRESSES.conduitRouter,
          abi: routerAbi,
          functionName: "getQuote",
          args: [productId, amountRaw],
        });

        setQuote(estimate as bigint);
      } catch {
        setQuote(fallbackQuote ?? amountRaw);
      }
    }, 400);

    return () => clearTimeout(timer);
  }, [amountRaw, fallbackQuote, productId]);

  return quote;
}
