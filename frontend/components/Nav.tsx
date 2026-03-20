"use client";

import Link from "next/link";
import { LayoutGrid, Terminal, Ticket, Wallet } from "lucide-react";
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
  { href: "/docs/agent-guide", label: "Docs" },
];

export function Nav() {
  const pathname = usePathname();
  const { address, connect, isConnecting } = useWallet();
  const isProductsActive = pathname === "/" || pathname.startsWith("/deposit");
  const isReceiptsActive = pathname === "/receipts";
  const isDocsActive = pathname.startsWith("/docs");

  return (
    <nav className="sticky top-0 z-50 h-14 border-b border-border bg-surface">
      <div className="mx-auto flex h-full w-full max-w-7xl items-center justify-between px-4 md:px-6">
        <Link
          href="/"
          className="font-display text-[14px] font-medium tracking-widest text-text-primary"
        >
          1CONDUIT
        </Link>

        <div className="flex items-center gap-4 sm:gap-5">
          <div className="flex items-center gap-3 sm:hidden">
            <Link
              href="/"
              title="Products"
              className={isProductsActive ? "text-accent" : "text-text-secondary hover:text-text-primary"}
            >
              <LayoutGrid size={16} strokeWidth={1.5} />
            </Link>
            <Link
              href="/receipts"
              title="Receipts"
              className={isReceiptsActive ? "text-accent" : "text-text-secondary hover:text-text-primary"}
            >
              <Ticket size={16} strokeWidth={1.5} />
            </Link>
            <Link
              href="/docs/agent-guide"
              title="Docs"
              className={isDocsActive ? "text-accent" : "text-text-secondary hover:text-text-primary"}
            >
              <Terminal size={16} strokeWidth={1.5} />
            </Link>
          </div>

          <div className="hidden items-center gap-5 sm:flex">
            {items.map((item) => {
              const active =
                (item.label === "Products" && isProductsActive) ||
                (item.label === "Receipts" && isReceiptsActive) ||
                (item.label === "Docs" && isDocsActive);

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
            <>
              <span className="hidden tabular font-data text-[13px] text-text-secondary sm:inline">
                {formatAddress(address)}
              </span>
              <span className="inline-flex items-center text-text-secondary sm:hidden" title={formatAddress(address)}>
                <Wallet size={16} strokeWidth={1.5} />
              </span>
            </>
          ) : (
            <button
              type="button"
              onClick={connect}
              disabled={isConnecting}
              className="ghost-button px-3 py-2"
              title="Connect Wallet"
            >
              <span className="hidden sm:inline">{isConnecting ? "Connecting..." : "Connect Wallet"}</span>
              <span className="inline sm:hidden">
                <Wallet size={16} strokeWidth={1.5} />
              </span>
            </button>
          )}
        </div>
      </div>
    </nav>
  );
}
