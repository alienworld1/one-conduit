import Link from "next/link";
import { CircleCheck, Ticket } from "lucide-react";
import type { DepositState } from "@/hooks/useDeposit";
import { formatTokenAmount } from "@/lib/format";
import { TOKEN_META } from "@/lib/contracts";

type TransactionStatusProps = {
  state: DepositState;
};

export function TransactionStatus({ state }: TransactionStatusProps) {
  if (state.status === "idle") return null;

  if (state.status === "approving") {
    if (state.phase === "signature") {
      return (
        <div className="rounded-sm border border-border bg-surface-2 p-3">
          <p className="text-[13px] font-body text-text-secondary">Awaiting wallet signature for approve...</p>
        </div>
      );
    }

    return (
      <div className="rounded-sm border border-border bg-surface-2 p-3">
        <p className="text-[13px] font-body text-text-secondary">Approve submitted. Waiting for chain confirmation...</p>
        {state.txHash && (
          <a
            href={`https://blockscout-testnet.polkadot.io/tx/${state.txHash}`}
            target="_blank"
            rel="noreferrer"
            className="mt-1 inline-block text-[11px] font-body text-accent underline"
          >
            View approve tx →
          </a>
        )}
      </div>
    );
  }

  if (state.status === "depositing") {
    if (state.phase === "signature") {
      return (
        <div className="rounded-sm border border-border bg-surface-2 p-3">
          <p className="text-[13px] font-body text-text-secondary">Awaiting wallet signature for deposit...</p>
        </div>
      );
    }

    return (
      <div className="rounded-sm border border-border bg-surface-2 p-3">
        <p className="text-[13px] font-body text-text-secondary">Deposit submitted. Waiting for chain confirmation (can take 1-2 minutes)...</p>
        {state.txHash && (
          <a
            href={`https://blockscout-testnet.polkadot.io/tx/${state.txHash}`}
            target="_blank"
            rel="noreferrer"
            className="mt-1 inline-block text-[11px] font-body text-accent underline"
          >
            View deposit tx →
          </a>
        )}
      </div>
    );
  }

  if (state.status === "error") {
    return <p className="text-[13px] font-body text-warning">⚠ {state.message}</p>;
  }

  const explorerUrl = `https://blockscout-testnet.polkadot.io/tx/${state.result.txHash}`;

  if (state.result.type === "local") {
    return (
      <div className="rounded-sm border border-success/30 bg-success/5 p-4">
        <div className="mb-2 flex items-center gap-2">
          <CircleCheck size={16} strokeWidth={1.5} className="text-success" />
          <span className="text-[13px] font-body text-success">Deposit confirmed</span>
        </div>
        <div className="text-[11px] font-body text-text-muted">
          Received {formatTokenAmount(BigInt(state.result.yieldTokens), TOKEN_META.cYLD.decimals)} {TOKEN_META.cYLD.symbol}
        </div>
        <a
          href={explorerUrl}
          target="_blank"
          rel="noreferrer"
          className="mt-2 inline-block text-[11px] font-body text-accent underline"
        >
          View transaction →
        </a>
      </div>
    );
  }

  return (
    <div className="rounded-sm border border-xcm/30 bg-xcm/5 p-4">
      <div className="mb-2 flex items-center gap-2">
        <Ticket size={16} strokeWidth={1.5} className="text-xcm" />
        <span className="text-[13px] font-body text-xcm">XCM dispatched</span>
      </div>
      <div className="mb-3 text-[11px] font-body text-text-muted">
        Receipt NFT #{state.result.receiptId} minted to your wallet
      </div>
      <div className="flex items-center gap-4">
        <Link href="/receipts" className="text-[11px] font-body text-accent underline">
          View in Receipts →
        </Link>
        <a
          href={explorerUrl}
          target="_blank"
          rel="noreferrer"
          className="text-[11px] font-body text-accent underline"
        >
          View transaction →
        </a>
      </div>
    </div>
  );
}
