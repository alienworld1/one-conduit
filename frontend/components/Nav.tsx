"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useWallet } from "@/hooks/useWallet";
import { formatAddress } from "@/lib/format";

type NavItem = {
  href: string;
  label: string;
};

const items: NavItem[] = [
  { href: "/", label: "Products" },
  { href: "/receipts", label: "Receipts" },
  { href: "/docs", label: "Docs" },
];

export function Nav() {
  const pathname = usePathname();
  const { address, connect, isConnecting } = useWallet();

  return (
    <nav className="sticky top-0 z-50 h-14 border-b border-border bg-surface">
      <div className="mx-auto flex h-full w-full max-w-7xl items-center justify-between px-4 md:px-6">
        <Link
          href="/"
          className="font-display text-[14px] font-medium tracking-widest text-text-primary"
        >
          1CONDUIT
        </Link>

        <div className="flex items-center gap-5">
          <div className="hidden items-center gap-5 sm:flex">
            {items.map((item) => {
              const active = pathname === item.href;

              return (
                <Link
                  key={item.href}
                  href={item.href}
                  className={[
                    "border-b pb-0.5 text-[13px] font-body transition-colors duration-120",
                    active
                      ? "border-accent text-text-primary"
                      : "border-transparent text-text-secondary hover:text-text-primary",
                  ].join(" ")}
                >
                  {item.label}
                </Link>
              );
            })}
          </div>

          {address ? (
            <span className="tabular font-data text-[13px] text-text-secondary">{formatAddress(address)}</span>
          ) : (
            <button
              type="button"
              onClick={connect}
              disabled={isConnecting}
              className="rounded-sm border border-border px-3 py-2 text-[13px] font-body tracking-wider text-text-secondary uppercase transition-colors duration-120 hover:border-text-muted hover:text-text-primary disabled:cursor-not-allowed disabled:opacity-40"
            >
              {isConnecting ? "Connecting..." : "Connect Wallet"}
            </button>
          )}
        </div>
      </div>
    </nav>
  );
}
