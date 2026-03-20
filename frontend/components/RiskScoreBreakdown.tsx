"use client";

import { useEffect, useState } from "react";
import type { Product } from "@/hooks/useProducts";
import { ADDRESSES, riskOracleAbi } from "@/lib/contracts";
import {
  computeAPYScore,
  computeMaturityScore,
  computeTVLScore,
  computeUtilScore,
} from "@/lib/scoring";
import { publicClient } from "@/lib/viem";
import { riskScoreColour } from "@/lib/format";

type ScoreInputs = {
  apyBps: bigint;
  tvlUSD: bigint;
  utilizationBps: bigint;
  contractAgeDays: bigint;
};

const DEFAULT_INPUTS: ScoreInputs = {
  apyBps: BigInt(0),
  tvlUSD: BigInt(0),
  utilizationBps: BigInt(0),
  contractAgeDays: BigInt(180),
};

export function RiskScoreBreakdown({ product }: { product: Product }) {
  const [score, setScore] = useState<bigint>(product.riskScore);
  const [inputs, setInputs] = useState<ScoreInputs>({
    apyBps: product.apyBps,
    tvlUSD: product.tvlUSD,
    utilizationBps: product.utilizationBps,
    contractAgeDays: BigInt(180),
  });
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let cancelled = false;

    async function loadRiskData() {
      setLoading(true);
      try {
        const currentScore = await publicClient.readContract({
          address: ADDRESSES.riskOracle,
          abi: riskOracleAbi,
          functionName: "getScore",
          args: [product.productId],
        });

        if (!cancelled) {
          setScore(currentScore as bigint);
        }

        try {
          const rawInputs = (await publicClient.readContract({
            address: ADDRESSES.riskOracle,
            abi: riskOracleAbi,
            functionName: "getScoreInputs",
            args: [BigInt(product.productId)],
          })) as {
            apyBps: bigint;
            tvlUSD: bigint;
            utilizationBps: bigint;
            contractAgeDays: bigint;
          };

          if (!cancelled) {
            setInputs(rawInputs);
          }
        } catch {
          // TODO(module10): switch fully to on-chain score inputs once oracle exposes getScoreInputs everywhere.
          if (!cancelled) {
            setInputs({
              apyBps: product.apyBps,
              tvlUSD: product.tvlUSD,
              utilizationBps: product.utilizationBps,
              contractAgeDays: BigInt(180),
            });
          }
        }
      } catch {
        if (!cancelled) {
          setScore(product.riskScore);
          setInputs(DEFAULT_INPUTS);
        }
      } finally {
        if (!cancelled) {
          setLoading(false);
        }
      }
    }

    loadRiskData();

    return () => {
      cancelled = true;
    };
  }, [product.apyBps, product.productId, product.riskScore, product.tvlUSD, product.utilizationBps]);

  if (loading) {
    return <div className="h-24" />;
  }

  const colour = riskScoreColour(score);
  const colourClass = {
    success: "text-success",
    yield: "text-yield",
    warning: "text-warning",
  }[colour];
  const barColourClass = {
    success: "bg-success",
    yield: "bg-yield",
    warning: "bg-warning",
  }[colour];

  const safeScore = Math.max(0, Math.min(100, Number(score)));
  const util = computeUtilScore(inputs.utilizationBps);
  const tvl = computeTVLScore(inputs.tvlUSD);
  const maturity = computeMaturityScore(inputs.contractAgeDays);
  const apy = computeAPYScore(inputs.apyBps);

  return (
    <div className="py-6">
      <div className={`tabular font-data text-[48px] leading-none ${colourClass}`}>{safeScore}</div>
      <div className="mt-3 h-1 w-30 bg-border">
        <div className={`h-full ${barColourClass}`} style={{ width: `${safeScore}%` }} />
      </div>
      <div className="mt-4 grid grid-cols-2 gap-x-6 gap-y-2 md:grid-cols-4">
        <Metric label="UTILISATION" value={util} />
        <Metric label="TVL" value={tvl} />
        <Metric label="MATURITY" value={maturity} />
        <Metric label="APY HEALTH" value={apy} />
      </div>
    </div>
  );
}

function Metric({ label, value }: { label: string; value: number }) {
  return (
    <div>
      <div className="mb-1 text-[10px] font-body tracking-widest text-text-muted uppercase">{label}</div>
      <div className="tabular font-data text-[13px] text-text-secondary">{value}</div>
    </div>
  );
}
