import type { Metadata, Viewport } from "next";

import "./globals.css";

export const metadata: Metadata = {
  title: "WTM Ops Console",
  // Keep the console out of search indexes (defense-in-depth; not security).
  robots: { index: false, follow: false },
};

// Mobile-first: device-width + no forced zoom so the console is usable on phones.
export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
