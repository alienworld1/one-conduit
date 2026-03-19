"use client";

import Link from "next/link";
import { Badge } from "@/components/Badge";
import { RiskScore } from "@/components/RiskScore";
import { useProducts } from "@/hooks/useProducts";
import { formatAPY, formatAddress, formatTVL } from "@/lib/format";

export function ProductTable() {
  const { products, loading, error } = useProducts();

  return (
    <div className="w-full">
      <div className="flex items-center justify-between py-8">
        <h1 className="font-display text-[28px] font-medium text-text-primary">Products</h1>
        <span className="font-body text-[11px] tracking-widest text-text-muted uppercase">
          Live on Paseo
        </span>
      </div>

      <table className="w-full table-fixed border-collapse">
        <colgroup>
          <col />
          <col className="w-20" />
          <col className="w-25" />
          <col className="w-30" />
          <col className="w-25" />
          <col className="w-22.5" />
          <col className="w-25" />
        </colgroup>

        <thead>
          <tr className="h-10 border-b border-border text-[11px] font-medium tracking-widest text-text-muted uppercase">
            <th className="text-left font-body">Product Name</th>
            <th className="text-left font-body">Token</th>
            <th className="text-right font-body">APY</th>
            <th className="text-right font-body">TVL</th>
            <th className="text-right font-body">Risk</th>
            <th className="text-center font-body">Path</th>
            <th className="text-right font-body">Action</th>
          </tr>
        </thead>

        <tbody>
          {loading &&
            Array.from({ length: 2 }).map((_, idx) => (
              <tr key={`loading-${idx}`} className="h-14 border-b border-border">
                <td colSpan={7} className="px-0">
                  <div className="flex h-14 items-center justify-center">
                    <span className="block h-px w-2/5 bg-border" />
                  </div>
                </td>
              </tr>
            ))}

          {!loading && error && (
            <tr className="h-14 border-b border-border">
              <td colSpan={7} className="text-center">
                <span className="font-body text-[13px] text-warning">⚠ Failed to load products: {error}</span>
              </td>
            </tr>
          )}

          {!loading && !error && products.length === 0 && (
            <tr className="h-14 border-b border-border">
              <td colSpan={7} className="text-center">
                <span className="font-body text-[13px] text-text-muted">
                  — No yield products registered —
                </span>
              </td>
            </tr>
          )}

          {!loading &&
            !error &&
            products.map((product) => {
              const token = product.isXCM ? "DOT" : "USDC";

              return (
                <tr
                  key={product.productId}
                  className="h-14 border-b border-border bg-transparent transition-colors duration-120 hover:bg-surface-2"
                >
                  <td className="pr-3 text-left">
                    <div className="flex flex-col">
                      <span className="font-body text-[14px] font-medium text-text-primary">
                        {product.name}
                      </span>
                      <span className="tabular font-data text-[11px] text-text-muted">
                        {formatAddress(product.adapterAddress)}
                      </span>
                    </div>
                  </td>

                  <td className="text-left">
                    <span className="tabular font-data text-[13px] text-text-secondary">{token}</span>
                  </td>

                  <td className="text-right">
                    <span className="tabular font-data text-[18px] text-yield">
                      {formatAPY(product.apyBps)}
                    </span>
                  </td>

                  <td className="text-right">
                    <span className="tabular font-data text-[13px] text-text-secondary">
                      {formatTVL(product.tvlUSD)}
                    </span>
                  </td>

                  <td className="text-right">
                    <RiskScore score={product.riskScore} />
                  </td>

                  <td className="text-center">
                    <Badge variant={product.isXCM ? "xcm" : "local"} />
                  </td>

                  <td className="text-right">
                    <Link
                      href={`/deposit/${product.productId}`}
                      className="inline-flex rounded-sm border border-border px-3 py-2 text-[11px] font-body tracking-widest text-text-secondary uppercase transition-colors duration-120 hover:border-text-muted hover:text-text-primary"
                    >
                      Deposit
                    </Link>
                  </td>
                </tr>
              );
            })}
        </tbody>
      </table>
    </div>
  );
}
