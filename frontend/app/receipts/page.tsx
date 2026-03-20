"use client";

import Link from "next/link";
import { Clock } from "lucide-react";
import { ReceiptCard } from "@/components/ReceiptCard";
import { useReceipts } from "@/hooks/useReceipts";
import { useWallet } from "@/hooks/useWallet";

export default function ReceiptsPage() {
  const { address, connect, isConnecting, error: walletError } = useWallet();
  const { receipts, loading, error, refetch } = useReceipts(address);

  return (
    <div className="mx-auto w-full max-w-7xl px-4 py-16 md:px-6">
      <div className="mb-8 flex items-center justify-between">
        <h1 className="font-display text-[28px] font-medium text-text-primary">Receipts</h1>
        <span className="font-body text-[11px] tracking-widest text-text-muted uppercase">XCM in-flight assets</span>
      </div>

      {!address ? (
        <div className="border border-border bg-surface p-12 text-center">
          <p className="mb-4 text-[13px] font-body text-text-secondary">
            Connect your wallet to view pending and settled receipt NFTs.
          </p>
          <button
            type="button"
            onClick={connect}
            disabled={isConnecting}
            className="rounded-sm border border-border px-4 py-2 text-[13px] font-body tracking-wider text-text-secondary uppercase transition-colors duration-120 hover:border-text-muted hover:text-text-primary disabled:cursor-not-allowed disabled:opacity-40"
          >
            {isConnecting ? "CONNECTING..." : "CONNECT WALLET"}
          </button>
          {walletError && <p className="mt-4 text-[13px] font-body text-warning">⚠ {walletError}</p>}
        </div>
      ) : null}

      {address && loading ? (
        <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
          {Array.from({ length: 2 }).map((_, index) => (
            <div key={`receipt-loading-${index}`} className="h-64 border border-border bg-surface-2">
              <div className="flex h-full items-center justify-center">
                <span className="block h-px w-2/5 bg-border" />
              </div>
            </div>
          ))}
        </div>
      ) : null}

      {address && !loading && error ? (
        <p className="text-[13px] font-body text-warning">⚠ {error}</p>
      ) : null}

      {address && !loading && !error && receipts.length === 0 ? (
        <div className="border border-border bg-surface p-12 text-center">
          <div className="mb-3 flex items-center justify-center text-text-muted">
            <Clock size={16} strokeWidth={1.5} />
          </div>
          <p className="text-[13px] font-body text-text-muted">— No receipts found —</p>
          <Link
            href="/"
            className="mt-4 inline-flex rounded-sm border border-border px-3 py-2 text-[11px] font-body tracking-widest text-text-secondary uppercase transition-colors duration-120 hover:border-text-muted hover:text-text-primary"
          >
            Browse Products
          </Link>
        </div>
      ) : null}

      {address && !loading && receipts.length > 0 ? (
        <div className="grid grid-cols-1 gap-4 lg:grid-cols-2">
          {receipts.map((receipt) => (
            <ReceiptCard
              key={receipt.tokenId.toString()}
              receipt={receipt}
              connectedAddress={address}
              onUpdate={refetch}
            />
          ))}
        </div>
      ) : null}
    </div>
  );
}
