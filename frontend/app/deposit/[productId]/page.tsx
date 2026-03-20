"use client";

import { useMemo } from "react";
import { useParams } from "next/navigation";
import { Badge } from "@/components/Badge";
import { DepositForm } from "@/components/DepositForm";
import { RiskScoreBreakdown } from "@/components/RiskScoreBreakdown";
import { useProducts } from "@/hooks/useProducts";
import { formatAPY, formatTVL } from "@/lib/format";

export default function DepositPage() {
  const params = useParams<{ productId: string }>();
  const productId = params.productId?.toLowerCase();
  const { products, loading } = useProducts();

  const product = useMemo(
    () => products.find((p) => p.productId.toLowerCase() === productId),
    [productId, products],
  );

  if (loading) {
    return (
      <div className="mx-auto w-full max-w-7xl px-4 py-16 md:px-6">
        <div className="h-40 border border-border bg-surface" />
      </div>
    );
  }

  if (!product) {
    return (
      <div className="mx-auto w-full max-w-7xl px-4 py-16 md:px-6">
        <div className="rounded-none border border-border bg-surface p-6">
          <h1 className="font-display text-[18px] font-medium text-text-primary">Product Not Found</h1>
          <p className="mt-2 text-[13px] font-body text-text-secondary">
            This product is not registered in the current on-chain catalog.
          </p>
        </div>
      </div>
    );
  }

  return (
    <div className="mx-auto w-full max-w-7xl px-4 py-16 md:px-6">
      <div className="grid grid-cols-1 gap-8 lg:grid-cols-5">
        <section className="lg:col-span-3">
          <h1 className="font-display text-[28px] font-medium text-text-primary">{product.name}</h1>
          <div className="mt-3">
            <Badge variant={product.isXCM ? "xcm" : "local"} />
          </div>

          <div className="mt-6 flex gap-8 border-y border-border py-5">
            <div>
              <div className="mb-1 text-[11px] font-body tracking-widest text-text-muted uppercase">APY</div>
              <div className="tabular font-data text-[24px] text-yield">{formatAPY(product.apyBps)}</div>
            </div>
            <div>
              <div className="mb-1 text-[11px] font-body tracking-widest text-text-muted uppercase">TVL</div>
              <div className="tabular font-data text-[24px] text-text-primary">{formatTVL(product.tvlUSD)}</div>
            </div>
            <div>
              <div className="mb-1 text-[11px] font-body tracking-widest text-text-muted uppercase">Utilisation</div>
              <div className="tabular font-data text-[24px] text-text-primary">
                {(Number(product.utilizationBps) / 100).toFixed(2)}%
              </div>
            </div>
          </div>

          <RiskScoreBreakdown product={product} />

          {product.isXCM && (
            <p className="text-[12px] font-body text-text-muted">
              Demo uses mock DOT. XCM dispatch is live on Paseo.
            </p>
          )}
        </section>

        <section className="lg:col-span-2">
          <DepositForm product={product} />
        </section>
      </div>
    </div>
  );
}
