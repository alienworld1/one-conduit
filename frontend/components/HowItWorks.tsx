"use client";

import { useState } from "react";
import { ChevronDown, ChevronUp } from "lucide-react";

const STEPS = [
  {
    number: "1",
    title: "BROWSE",
    body: "Both LOCAL and XCM products appear below. LOCAL deposits settle in one transaction. XCM deposits lock funds and dispatch a cross-chain message.",
  },
  {
    number: "2",
    title: "DEPOSIT",
    body: "Connect your wallet and deposit in one transaction. The router handles approvals, risk scoring, and adapter routing.",
  },
  {
    number: "3",
    title: "TRACK & SETTLE",
    body: "XCM deposits mint a PendingReceipt NFT to your wallet. Transfer it before settlement, whoever holds it receives the yield.",
  },
];

export function HowItWorks() {
  const [open, setOpen] = useState(false);

  return (
    <div className="mb-8 border border-border rounded-none">
      <button
        type="button"
        onClick={() => setOpen((current) => !current)}
        className="flex w-full cursor-pointer items-center justify-between px-4 py-3 text-left transition-colors duration-[120ms] hover:bg-surface-2"
      >
        <span className="font-body text-[11px] tracking-widest text-text-muted uppercase">
          HOW IT WORKS
        </span>
        {open ? (
          <ChevronUp size={14} strokeWidth={1.5} className="text-text-muted" />
        ) : (
          <ChevronDown size={14} strokeWidth={1.5} className="text-text-muted" />
        )}
      </button>

      {open && (
        <div className="border-t border-border">
          {STEPS.map((step, index) => (
            <div
              key={step.number}
              className={`flex gap-5 px-4 py-4 ${index < STEPS.length - 1 ? "border-b border-border" : ""}`}
            >
              <span className="tabular w-6 shrink-0 font-data text-[24px] leading-none text-text-muted">
                {step.number}
              </span>

              <div>
                <div className="mb-1 font-body text-[11px] tracking-widest text-text-muted uppercase">
                  {step.title}
                </div>
                <p className="font-body text-[13px] leading-relaxed text-text-secondary">{step.body}</p>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}