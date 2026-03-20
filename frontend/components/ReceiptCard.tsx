"use client";

import { useMemo, useState } from "react";
import { CircleCheck, Copy, Send, Terminal, Ticket } from "lucide-react";
import type { Address } from "viem";
import { Badge } from "@/components/Badge";
import { TransferModal } from "@/components/TransferModal";
import type { Receipt } from "@/hooks/useReceipts";
import { ADDRESSES, receiptNFTAbi, XCM_PRODUCT_ID } from "@/lib/contracts";
import { formatAddress } from "@/lib/format";
import { publicClient } from "@/lib/viem";

type ReceiptCardProps = {
  receipt: Receipt;
  connectedAddress: Address | null;
  onUpdate: () => void;
};

function formatTokenAmount(amount: bigint, decimals = 6): string {
  const divisor = BigInt(10) ** BigInt(decimals);
  const whole = amount / divisor;
  const frac = amount % divisor;
  return `${whole}.${frac.toString().padStart(decimals, "0")}`;
}

function SettleButton({
  receiptId,
  onSettled,
}: {
  receiptId: bigint;
  onSettled: () => void;
}) {
  const [copied, setCopied] = useState(false);
  const [polling, setPolling] = useState(false);

  const relayerCommand = `npx tsx scripts/relayer.ts settle ${receiptId}`;

  function startPolling() {
    setPolling(true);
    const interval = setInterval(async () => {
      const settled = await publicClient
        .readContract({
          address: ADDRESSES.pendingReceiptNFT,
          abi: receiptNFTAbi,
          functionName: "isSettled",
          args: [receiptId],
        })
        .then((value) => value as boolean)
        .catch(() => false);

      if (settled) {
        clearInterval(interval);
        setPolling(false);
        onSettled();
      }
    }, 4000);

    setTimeout(() => {
      clearInterval(interval);
      setPolling(false);
    }, 300_000);
  }

  function handleSettle() {
    navigator.clipboard
      .writeText(relayerCommand)
      .then(() => {
        setCopied(true);
      })
      .catch(() => {
        setCopied(false);
      });

    if (!polling) {
      startPolling();
    }
  }

  return (
    <div className="flex-1">
      <button
        type="button"
        onClick={handleSettle}
        disabled={polling}
        className={[
          "w-full rounded-sm px-4 py-2 text-[11px] font-body tracking-widest text-white uppercase transition-colors duration-120",
          polling ? "cursor-not-allowed bg-accent/40" : "bg-accent hover:bg-accent-dim",
        ].join(" ")}
      >
        {polling ? "WATCHING SETTLEMENT..." : copied ? "COMMAND COPIED" : "COPY + START WATCH"}
      </button>

      <div className="mt-3 border border-border bg-surface p-3">
        <div className="mb-2 flex items-center gap-1.5 text-text-primary">
          <Terminal size={14} strokeWidth={1.5} />
          <span className="text-[11px] font-body tracking-widest uppercase">Relayer Step Required</span>
        </div>
        <p className="mb-2 text-[12px] font-body text-text-secondary">
          Run this command in a terminal with the project checked out. The card will auto-update when on-chain settlement is detected.
        </p>
        <div className="rounded-sm border border-border-subtle bg-void px-3 py-2">
          <p className="tabular break-all font-data text-[12px] text-text-primary">{relayerCommand}</p>
        </div>
        <div className="mt-2 space-y-1">
          {copied ? (
            <p className="text-[11px] font-body text-success">Command copied to clipboard.</p>
          ) : (
            <p className="text-[11px] font-body text-text-muted">Use the button above to copy the command.</p>
          )}
          {polling ? (
            <p className="text-[11px] font-body text-text-muted">Watching every 4s for up to 5 minutes.</p>
          ) : (
            <p className="text-[11px] font-body text-text-muted">After running the command, click this button again to start watching settlement.</p>
          )}
        </div>
      </div>
    </div>
  );
}

export function ReceiptCard({ receipt, connectedAddress, onUpdate }: ReceiptCardProps) {
  const [showTransferModal, setShowTransferModal] = useState(false);
  const [settledInSession, setSettledInSession] = useState(false);
  const justSettled = settledInSession || receipt.settled;

  const isCurrentHolder = useMemo(() => {
    if (!connectedAddress || !receipt.currentOwner) {
      return false;
    }

    return receipt.currentOwner.toLowerCase() === connectedAddress.toLowerCase();
  }, [connectedAddress, receipt.currentOwner]);

  const isTransferredAway = !receipt.settled && !isCurrentHolder && receipt.currentOwner !== null;
  const isPending = !receipt.settled && isCurrentHolder;

  const amountLabel = `${formatTokenAmount(receipt.amount)} DOT`;
  const isXcmProduct = receipt.productId.toLowerCase() === XCM_PRODUCT_ID.toLowerCase();
  const leftBorderClass = justSettled ? "border-l-success" : "border-l-xcm";

  return (
    <div className={`relative overflow-hidden border border-border border-l-[3px] bg-surface-2 p-6 ${leftBorderClass}`}>
      <div
        className="absolute inset-0 pointer-events-none transition-opacity duration-400"
        style={{
          opacity: justSettled ? 0 : 1,
          background:
            "repeating-linear-gradient(45deg, transparent, transparent 8px, var(--color-border-subtle) 8px, var(--color-border-subtle) 9px)",
        }}
      />
      {isPending ? (
        <div
          className="absolute inset-y-0 left-0 w-0.75 bg-xcm"
          style={{ animation: "border-pulse 2s ease-in-out infinite" }}
        />
      ) : null}

      <div className="relative z-10">
        <div className="mb-4 flex items-start justify-between">
          <div>
            <div className="font-data text-[11px] tracking-widest text-text-muted uppercase">
              Receipt #{receipt.tokenId.toString()}
            </div>
            <div className="mt-1 text-[11px] font-body text-text-secondary">Block #{receipt.dispatchBlock.toString()}</div>
          </div>
          <div className="flex items-center gap-2">
            {justSettled ? <Badge variant="settled" /> : <Badge variant="pending" />}
            {isXcmProduct ? <Badge variant="xcm" /> : <Badge variant="local" />}
          </div>
        </div>

        <div className="mb-5 flex items-center gap-2 text-text-primary">
          <Ticket size={16} strokeWidth={1.5} />
          <div className="tabular font-data text-[28px] leading-none">{amountLabel}</div>
        </div>

        <div className="mb-5 grid grid-cols-2 gap-3 border-y border-border py-4">
          <div>
            <div className="mb-1 text-[11px] font-body tracking-widest text-text-muted uppercase">Depositor</div>
            <div className="tabular font-data text-[13px] text-text-secondary">
              {formatAddress(receipt.originalDepositor)}
            </div>
          </div>
          <div>
            <div className="mb-1 text-[11px] font-body tracking-widest text-text-muted uppercase">Current Holder</div>
            <div className="tabular font-data text-[13px] text-text-secondary">
              {receipt.currentOwner ? formatAddress(receipt.currentOwner) : "Burned"}
            </div>
          </div>
        </div>

        <div className={`transition-opacity duration-400 ${justSettled ? "opacity-0 pointer-events-none" : "opacity-100"}`}>
          {isPending ? (
            <div className="flex gap-3">
              <button
                type="button"
                onClick={() => setShowTransferModal(true)}
                className="flex flex-1 items-center justify-center gap-1.5 rounded-sm border border-border px-4 py-2 text-[11px] font-body tracking-widest text-text-secondary uppercase transition-colors duration-120 hover:border-text-muted hover:text-text-primary"
              >
                <Send size={14} strokeWidth={1.5} />
                Transfer
              </button>
              <SettleButton
                receiptId={receipt.tokenId}
                onSettled={() => {
                  setSettledInSession(true);
                  onUpdate();
                }}
              />
            </div>
          ) : null}

          {isTransferredAway ? (
            <div className="rounded-sm border border-border px-4 py-3 text-center text-[12px] font-body text-text-secondary">
              Transferred to {receipt.currentOwner ? formatAddress(receipt.currentOwner) : "another holder"}
            </div>
          ) : null}
        </div>

        <div className={`flex items-center gap-2 transition-opacity duration-400 ${justSettled ? "opacity-100" : "opacity-0"}`}>
          <CircleCheck size={16} strokeWidth={1.5} className="text-success" />
          <span className="text-[13px] font-body text-success">Position settled</span>
          <button
            type="button"
            onClick={onUpdate}
            className="ml-auto inline-flex items-center gap-1 text-[11px] font-body tracking-widest text-text-muted uppercase transition-colors duration-120 hover:text-text-primary"
          >
            <Copy size={13} strokeWidth={1.5} />
            Refresh
          </button>
        </div>
      </div>

      {showTransferModal && (
        <TransferModal
          receiptId={receipt.tokenId}
          onClose={() => setShowTransferModal(false)}
          onTransferred={onUpdate}
        />
      )}
    </div>
  );
}
