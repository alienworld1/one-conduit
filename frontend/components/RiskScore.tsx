import { formatRiskScore, riskScoreColour } from "@/lib/format";

export function RiskScore({ score }: { score: bigint }) {
  const colour = riskScoreColour(score);
  const classes = {
    success: "text-success",
    yield: "text-yield",
    warning: "text-warning",
  }[colour];

  return (
    <span className={`tabular font-data text-[18px] leading-none ${classes}`}>
      {formatRiskScore(score)}
    </span>
  );
}
