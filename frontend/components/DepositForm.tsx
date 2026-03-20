"use client";

import { useEffect, useMemo, useState } from "react";
import type { Product } from "@/hooks/useProducts";
import { AmountInput } from "@/components/AmountInput";
import { TransactionStatus } from "@/components/TransactionStatus";
import { useQuote } from "@/hooks/useQuote";
import { useDeposit } from "@/hooks/useDeposit";
import { useWallet } from "@/hooks/useWallet";
import { formatTokenAmount } from "@/lib/format";
import { erc20Abi, TOKEN_META } from "@/lib/contracts";
import { publicClient } from "@/lib/viem";

function parseAmount(display: string, decimals: number): bigint {
  const [whole, frac = ""] = display.split(".");
  const fracPadded = frac.padEnd(decimals, "0").slice(0, decimals);
  const base = BigInt(10) ** BigInt(decimals);

  return BigInt(whole || "0") * base + BigInt(fracPadded || "0");
}

export function DepositForm({ product }: { product: Product }) {
  const { address, walletClient, connect, isConnecting, error: walletError } = useWallet();
  const { state, deposit, reset } = useDeposit(product);
  const [amount, setAmount] = useState("");
  const [minRiskScore, setMinRiskScore] = useState(60);
  const [walletBalance, setWalletBalance] = useState<bigint | null>(null);

  const token = product.isXCM ? TOKEN_META.mockDOT : TOKEN_META.mUSDC;
  const amountRaw = useMemo(() => parseAmount(amount, token.decimals), [amount, token.decimals]);
  const quote = useQuote(product.productId, amountRaw, amountRaw);

  useEffect(() => {
    if (!address) {
      setWalletBalance(null);
      return;
    }

    publicClient
      .readContract({
        address: token.address,
        abi: erc20Abi,
        functionName: "balanceOf",
        args: [address],
      })
      .then((balance) => setWalletBalance(balance as bigint))
      .catch(() => setWalletBalance(null));
  }, [address, token.address]);

  const buttonConfig = {
    idle: { label: "DEPOSIT", disabled: false },
    approving: { label: "APPROVING...", disabled: true },
    depositing: { label: "CONFIRMING...", disabled: true },
    confirmed: { label: "DEPOSIT AGAIN", disabled: false },
    error: { label: "TRY AGAIN", disabled: false },
  } as const;

  const current = buttonConfig[state.status];

  async function onDeposit() {
    if (state.status === "confirmed" || state.status === "error") {
      reset();
    }
    await deposit(amountRaw, BigInt(minRiskScore), walletClient, address);
  }

  if (!address) {
    return (
      <div className="rounded-sm border border-border bg-surface p-6 text-center">
        <p className="mb-4 text-[13px] font-body text-text-secondary">
          Connect your wallet to deposit into this product.
        </p>
        <button
          type="button"
          onClick={connect}
          disabled={isConnecting}
          className="rounded-sm border border-border px-4 py-2 text-[13px] font-body tracking-wider text-text-secondary uppercase transition-colors duration-120 hover:border-text-muted hover:text-text-primary"
        >
          {isConnecting ? "CONNECTING..." : "CONNECT WALLET"}
        </button>
        {walletError && <p className="mt-4 text-[13px] font-body text-warning">⚠ {walletError}</p>}
      </div>
    );
  }

  return (
    <div className="rounded-none border border-border bg-surface p-6">
      <div className="space-y-5">
        <AmountInput
          value={amount}
          onChange={setAmount}
          symbol={token.symbol}
          decimals={token.decimals}
          disabled={state.status === "approving" || state.status === "depositing"}
        />

        <div className="text-[11px] font-body text-text-muted">
          Wallet balance:{" "}
          {walletBalance !== null
            ? `${formatTokenAmount(walletBalance, token.decimals)} ${token.symbol}`
            : "—"}
        </div>

        <div className="rounded-sm border border-border bg-surface p-4">
          <div className="mb-1 text-[11px] font-body tracking-widest text-text-muted uppercase">
            Estimated output
          </div>
          <div className="tabular font-data text-[18px] text-text-primary">
            {amountRaw > BigInt(0) && quote !== null
              ? `${formatTokenAmount(quote, token.decimals)} ${token.symbol}`
              : "—"}
          </div>
        </div>

        <div>
          <div className="mb-2 flex items-center justify-between">
            <label className="text-[11px] font-body tracking-widest text-text-muted uppercase">
              Minimum risk score
            </label>
            <span className="tabular font-data text-[13px] text-text-primary">{minRiskScore}</span>
          </div>
          <input
            type="range"
            min={0}
            max={100}
            value={minRiskScore}
            onChange={(e) => setMinRiskScore(Number(e.target.value))}
            className="w-full accent-accent"
          />
          <div className="mt-1 flex justify-between">
            <span className="text-[10px] font-body text-text-muted">Any</span>
            <span className="text-[10px] font-body text-text-muted">Strict</span>
          </div>
        </div>

        <button
          type="button"
          disabled={current.disabled || amountRaw === BigInt(0)}
          onClick={onDeposit}
          className={[
            "w-full rounded-sm px-5 py-2.5 text-[13px] font-body tracking-wider text-white uppercase transition-colors duration-120",
            current.disabled || amountRaw === BigInt(0)
              ? "cursor-not-allowed bg-accent/40"
              : "bg-accent hover:bg-accent-dim",
            state.status === "approving" || state.status === "depositing" ? "btn-shimmer" : "",
          ].join(" ")}
        >
          {current.label}
        </button>

        <TransactionStatus state={state} />
      </div>
    </div>
  );
}
