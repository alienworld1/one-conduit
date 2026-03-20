"use client";

import Link from "next/link";
import { Clock } from "lucide-react";
import { ErrorBoundary } from "@/components/ErrorBoundary";
import { PageWrapper } from "@/components/PageWrapper";
import { ReceiptCard } from "@/components/ReceiptCard";
import { useReceipts } from "@/hooks/useReceipts";
import { useWallet } from "@/hooks/useWallet";

export default function ReceiptsPage() {
  const { address, connect, isConnecting, error: walletError } = useWallet();
  const { receipts, loading, error, refetch } = useReceipts(address);

  return (
    <PageWrapper>
      <ErrorBoundary>
        <div className="mx-auto w-full max-w-7xl px-4 py-16 md:px-6">
          <div className="mb-8 flex items-center justify-between">
            <h1 className="font-display text-[28px] font-medium text-text-primary">Receipts</h1>
            <span className="font-body text-[11px] tracking-widest text-text-muted uppercase">XCM in-flight assets</span>
          </div>

          {address ? (
            <div className="mb-6 border border-border bg-surface p-4">
              <p className="text-[11px] font-body tracking-widest text-text-muted uppercase">Settlement Guide</p>
              <p className="mt-2 text-[13px] font-body text-text-secondary">
                Settlement is relayer-assisted in v1. Use the command shown on each pending receipt card to trigger on-chain settlement.
              </p>
              <p className="mt-1 text-[13px] font-body text-text-secondary">
                Step 1: Copy the command from the card. Step 2: Run it in a terminal. Step 3: The card detects settlement automatically.
              </p>
            </div>
          ) : null}

          {!address ? (
            <div className="border border-border bg-surface p-12 text-center">
              <p className="mb-4 text-[13px] font-body text-text-secondary">
                Connect your wallet to view pending and settled receipt NFTs.
              </p>
              <button
                type="button"
                onClick={connect}
                disabled={isConnecting}
                className="ghost-button"
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
              <Link href="/" className="ghost-button mt-4 text-[11px] tracking-widest">
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
      </ErrorBoundary>
    </PageWrapper>
  );
}
