export function computeUtilScore(utilizationBps: bigint): number {
  const u = Number(utilizationBps);
  return Math.max(0, 100 - Math.floor((u * 100) / 10_000));
}

export function computeTVLScore(tvlUSD: bigint): number {
  return Math.min(100, Math.floor((Number(tvlUSD) * 100) / 10_000_000));
}

export function computeMaturityScore(days: bigint): number {
  return Math.min(100, Math.floor((Number(days) * 100) / 180));
}

export function computeAPYScore(apyBps: bigint): number {
  const a = Number(apyBps);

  if (a <= 2_000) return 100;
  if (a >= 10_000) return 0;

  return 100 - Math.floor(((a - 2_000) * 100) / 8_000);
}
