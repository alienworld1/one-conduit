import type { Metadata } from "next";
import { DM_Mono, IBM_Plex_Sans } from "next/font/google";
import { Nav } from "@/components/Nav";
import "./globals.css";

const dmMono = DM_Mono({
  subsets: ["latin"],
  weight: ["400", "500"],
  variable: "--font-display",
  display: "swap",
});

const ibmPlexSans = IBM_Plex_Sans({
  subsets: ["latin"],
  weight: ["400", "500"],
  variable: "--font-body",
  display: "swap",
});

export const metadata: Metadata = {
  title: "1Conduit",
  description: "Cross-protocol yield aggregator for Polkadot Hub",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html
      lang="en"
      className={`${dmMono.variable} ${ibmPlexSans.variable} h-full antialiased`}
    >
      <body className="min-h-full bg-void text-text-primary font-body">
        <Nav />
        <main className="flex-1">{children}</main>
      </body>
    </html>
  );
}
