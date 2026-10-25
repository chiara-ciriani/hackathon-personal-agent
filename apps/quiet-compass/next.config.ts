import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  async rewrites() {
    return [{ source: "/demo", destination: "/demo.html" }];
  },
  ...(process.env.VERCEL
    ? { turbopack: { resolveAlias: { "cloudflare:workers": "./lib/cloudflare-workers-shim.ts" } } }
    : {}),
};

export default nextConfig;
