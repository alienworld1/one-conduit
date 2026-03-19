type BadgeVariant = "local" | "xcm" | "settled" | "pending";

export function Badge({ variant }: { variant: BadgeVariant }) {
  const label: Record<BadgeVariant, string> = {
    local: "LOCAL",
    xcm: "XCM",
    settled: "SETTLED",
    pending: "PENDING",
  };

  const styles: Record<BadgeVariant, string> = {
    local: "border-border text-text-secondary",
    xcm: "border-xcm/60 text-xcm",
    settled: "border-success/60 text-success",
    pending: "border-yield/60 text-yield",
  };

  return (
    <span
      className={`inline-flex rounded border px-2 py-0.5 font-body text-[11px] tracking-widest ${styles[variant]}`}
    >
      {label[variant]}
    </span>
  );
}
