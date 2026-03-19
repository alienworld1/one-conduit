"use client";

import { useEffect, useState } from "react";
import { type Address } from "viem";
import { ADDRESSES, registryAbi } from "@/lib/contracts";
import { publicClient } from "@/lib/viem";

export type Product = {
  productId: `0x${string}`;
  adapterAddress: Address;
  name: string;
  isXCM: boolean;
  apyBps: bigint;
  tvlUSD: bigint;
  utilizationBps: bigint;
  lastUpdated: bigint;
  riskScore: bigint;
};

export function useProducts() {
  const [products, setProducts] = useState<Product[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;

    async function loadProducts() {
      setLoading(true);
      setError(null);

      try {
        const rawProducts = await publicClient.readContract({
          address: ADDRESSES.conduitRegistry,
          abi: registryAbi,
          functionName: "getAllProducts",
        });

        if (!cancelled) {
          setProducts(rawProducts as Product[]);
        }
      } catch (err) {
        if (!cancelled) {
          const message = err instanceof Error ? err.message : "Failed to load products";
          setError(message);
        }
      } finally {
        if (!cancelled) {
          setLoading(false);
        }
      }
    }

    loadProducts();

    return () => {
      cancelled = true;
    };
  }, []);

  return { products, loading, error };
}
