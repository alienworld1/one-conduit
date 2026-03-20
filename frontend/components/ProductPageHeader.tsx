interface StatChipProps {
  label: string;
  value: string;
}

function StatChip({ label, value }: StatChipProps) {
  return (
    <div className="flex items-center gap-2 border border-border px-3 py-1.5">
      <span className="font-body text-[10px] tracking-widest text-text-muted uppercase">{label}</span>
      <span className="tabular font-data text-[13px] text-text-secondary">{value}</span>
    </div>
  );
}

export function ProductPageHeader() {
  return (
    <div className="mb-6">
      <p className="mb-4 font-body text-[13px] leading-relaxed text-text-secondary">
        Deposit into any registered yield product, local Hub lending or XCM-dispatched
        parachain positions, in a single transaction. In-flight XCM positions mint a
        transferable receipt NFT.
      </p>

      <div className="flex flex-wrap items-center gap-3">
        <StatChip label="PRODUCTS" value="2" />
        <span className="text-[11px] text-text-muted">·</span>
        <StatChip label="CHAINS" value="2" />
        <span className="text-[11px] text-text-muted">·</span>
        <StatChip label="NETWORK" value="PASEO ASSET HUB" />
      </div>
    </div>
  );
}