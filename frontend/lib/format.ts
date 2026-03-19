// APY in basis points: 800 -> 8.00%
export function formatAPY(apyBps: bigint): string {
  const pct = Number(apyBps) / 100;
  return `${pct.toFixed(2)}%`;
}

// TVL in USD units (already integer dollars from registry cache).
export function formatTVL(tvlUSD: bigint): string {
  const n = Number(tvlUSD);

  if (n >= 1_000_000) return `$${(n / 1_000_000).toFixed(1)}M`;
  if (n >= 1_000) return `$${(n / 1_000).toFixed(0)}K`;

  return `$${n.toLocaleString()}`;
}

export function formatRiskScore(score: bigint): string {
  return score.toString();
}

export function formatAddress(addr: string): string {
  return `${addr.slice(0, 6)}…${addr.slice(-4)}`;
}

export function formatTokenAmount(amount: bigint, decimals: number): string {
  const divisor = BigInt(10) ** BigInt(decimals);
  const whole = amount / divisor;
  const frac = amount % divisor;

  return `${whole}.${frac.toString().padStart(decimals, "0")}`;
}

export function riskScoreColour(score: bigint): "success" | "yield" | "warning" {
  const n = Number(score);

  if (n > 70) return "success";
  if (n >= 40) return "yield";

  return "warning";
}
