"use client";

import { useState } from "react";
import { X } from "lucide-react";
import type { Address } from "viem";
import { ADDRESSES, receiptNFTAbi } from "@/lib/contracts";
import { paseoAssetHub, publicClient } from "@/lib/viem";
import { useWallet } from "@/hooks/useWallet";

type TransferModalProps = {
  receiptId: bigint;
  onClose: () => void;
  onTransferred: () => void;
};

const addressRegex = /^0x[0-9a-fA-F]{40}$/;

export function TransferModal({ receiptId, onClose, onTransferred }: TransferModalProps) {
  const { walletClient, address } = useWallet();
  const [to, setTo] = useState("");
  const [status, setStatus] = useState<"idle" | "pending" | "done" | "error">("idle");
  const [errorMessage, setErrorMessage] = useState("");

  const isValidAddress = addressRegex.test(to);

  async function handleTransfer() {
    if (!walletClient || !address || !isValidAddress) {
      return;
    }

    setStatus("pending");
    setErrorMessage("");

    try {
      const txHash = await walletClient.writeContract({
        address: ADDRESSES.pendingReceiptNFT,
        abi: receiptNFTAbi,
        functionName: "transferFrom",
        args: [address, to as Address, receiptId],
        account: address,
        chain: paseoAssetHub,
      });

      await publicClient.waitForTransactionReceipt({ hash: txHash });

      setStatus("done");
      setTimeout(() => {
        onTransferred();
        onClose();
      }, 1200);
    } catch (err) {
      const message = err instanceof Error ? err.message : "Transfer failed.";
      setErrorMessage(message.toLowerCase().includes("user rejected") ? "Transaction rejected." : "Transfer failed.");
      setStatus("error");
    }
  }

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/65 p-4"
      onClick={onClose}
    >
      <div className="w-full max-w-md border border-border bg-surface p-6" onClick={(event) => event.stopPropagation()}>
        <div className="mb-6 flex items-center justify-between">
          <h2 className="font-display text-[18px] font-medium text-text-primary">Transfer Receipt</h2>
          <button
            type="button"
            onClick={onClose}
            className="rounded-sm border border-border p-1.5 text-text-secondary transition-colors duration-120 hover:border-text-muted hover:text-text-primary"
            aria-label="Close transfer modal"
          >
            <X size={16} strokeWidth={1.5} />
          </button>
        </div>

        <label className="mb-2 block text-[11px] font-body tracking-widest text-text-muted uppercase">
          Recipient Address
        </label>
        <input
          type="text"
          value={to}
          onChange={(event) => setTo(event.target.value.trim())}
          placeholder="0x..."
          className="w-full border border-border bg-surface-2 px-4 py-3 font-data text-[13px] text-text-primary placeholder:text-text-muted focus:border-accent focus:outline-none"
        />

        <div className="mt-6 flex gap-3">
          <button
            type="button"
            onClick={onClose}
            className="ghost-button flex-1 px-4 py-2 text-[11px] tracking-widest"
          >
            Cancel
          </button>
          <button
            type="button"
            onClick={handleTransfer}
            disabled={!isValidAddress || status === "pending" || status === "done"}
            className={[
              "primary-button flex-1 px-4 py-2 text-[11px] tracking-widest",
              status === "pending" ? "shimmer" : "",
            ].join(" ")}
          >
            {status === "pending" ? "Sending..." : status === "done" ? "Sent" : "Confirm Transfer"}
          </button>
        </div>

        {!isValidAddress && to.length > 0 && (
          <p className="mt-3 text-[13px] font-body text-warning">⚠ Enter a valid 0x address.</p>
        )}
        {status === "error" && errorMessage && (
          <p className="mt-3 text-[13px] font-body text-warning">⚠ {errorMessage}</p>
        )}
      </div>
    </div>
  );
}
