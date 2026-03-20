"use client";

import { useCallback, useEffect, useState } from "react";
import { createWalletClient, custom, type WalletClient } from "viem";
import { paseoAssetHub } from "@/lib/viem";

type EIP1193Provider = {
  request: (args: { method: string; params?: unknown[] }) => Promise<unknown>;
  on?: (event: string, listener: (...args: unknown[]) => void) => void;
  removeListener?: (event: string, listener: (...args: unknown[]) => void) => void;
};

export type WalletState = {
  address: `0x${string}` | null;
  walletClient: WalletClient | null;
  isConnecting: boolean;
  error: string | null;
  connect: () => Promise<void>;
};

function getProvider(): EIP1193Provider | undefined {
  if (typeof window === "undefined") return undefined;
  return (window as Window & { ethereum?: EIP1193Provider }).ethereum;
}

export function useWallet(): WalletState {
  const [address, setAddress] = useState<`0x${string}` | null>(null);
  const [walletClient, setWalletClient] = useState<WalletClient | null>(null);
  const [isConnecting, setIsConnecting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const setConnected = useCallback((addr: `0x${string}`) => {
    const provider = getProvider();
    if (!provider) return;

    setAddress(addr);
    setWalletClient(
      createWalletClient({
        account: addr,
        chain: paseoAssetHub,
        transport: custom(provider),
      }),
    );
  }, []);

  const connect = useCallback(async () => {
    const provider = getProvider();
    if (!provider) {
      setError("No wallet detected. Install MetaMask or Talisman.");
      return;
    }

    setIsConnecting(true);
    setError(null);

    try {
      const accounts = (await provider.request({
        method: "eth_requestAccounts",
      })) as `0x${string}`[];

      if (!accounts.length) {
        setError("No wallet account available.");
        return;
      }

      setConnected(accounts[0]);
    } catch (err) {
      const message = err instanceof Error ? err.message : "Wallet connection failed.";
      if (message.toLowerCase().includes("user rejected")) {
        setError("Connection request rejected in wallet.");
      } else {
        setError(message);
      }
    } finally {
      setIsConnecting(false);
    }
  }, [setConnected]);

  useEffect(() => {
    const provider = getProvider();
    if (!provider) return;

    provider
      .request({ method: "eth_accounts" })
      .then((accounts) => {
        const existing = (accounts as `0x${string}`[])[0];
        if (existing) {
          setConnected(existing);
        }
      })
      .catch(() => {});

    const onAccountsChanged = (nextAccounts: unknown) => {
      const account = (nextAccounts as `0x${string}`[])[0] ?? null;
      if (!account) {
        setAddress(null);
        setWalletClient(null);
        return;
      }
      setConnected(account);
    };

    provider.on?.("accountsChanged", onAccountsChanged);

    return () => {
      provider.removeListener?.("accountsChanged", onAccountsChanged);
    };
  }, [setConnected]);

  return { address, walletClient, isConnecting, error, connect };
}
