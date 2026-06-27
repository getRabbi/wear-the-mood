import type { NextConfig } from "next";

// The admin console is mounted under an intentionally obscure base path. This is
// NOT the security boundary (auth + admin_users allowlist + per-action re-checks
// are) — it only reduces random discovery. Configurable per environment.
const basePath = process.env.ADMIN_PANEL_BASE_PATH || "/mood-ops-console-7x9";

const nextConfig: NextConfig = {
  basePath,
  // Standalone output → a self-contained server bundle for the Phase 8 Docker
  // deploy on the DigitalOcean droplet (no node_modules shipped at runtime).
  output: "standalone",
  poweredByHeader: false,
  // Allow image uploads (seed avatars / look photos) through Server Actions.
  experimental: { serverActions: { bodySizeLimit: "8mb" } },
  // Build verification stays decoupled from lint: `npm run lint` is the gate for
  // style, `next build` is the gate for type-safety + bundling. (Type errors
  // still fail the build — see the absence of typescript.ignoreBuildErrors.)
  eslint: { ignoreDuringBuilds: true },
  async headers() {
    // Belt-and-suspenders: keep the whole console out of search indexes. Real
    // security is auth/RBAC, never noindex.
    return [
      {
        source: "/:path*",
        headers: [{ key: "X-Robots-Tag", value: "noindex, nofollow" }],
      },
    ];
  },
};

export default nextConfig;
