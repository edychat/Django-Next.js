import type { NextConfig } from 'next';
import createNextIntlPlugin from 'next-intl/plugin';

const withNextIntl = createNextIntlPlugin('./i18n/request.ts');

// Build the allowedDevOrigins list dynamically so no hostname is hardcoded.
//
// Why this matters:
//   Next.js 15.2.3+ validates the `Origin` header on every dev server request
//   (including WebSocket upgrades). If the origin isn't in the allowed list the
//   request gets a 403 and hot reload silently dies in the browser.
//
//   We add three layers of coverage so HMR always works:
//     1. Exact hostname  →  oldbook.ai.localhost  (read from PROJECT_HOST env)
//     2. Wildcard        →  *.localhost            (covers any subdomain)
//     3. Tunnel URL      →  *.trycloudflare.com    (Cloudflare dev tunnel)
//     4. Explicit tunnel →  analog-utilities-…     (exact current tunnel host)
//
//   Layers 1 and 4 are the critical ones — wildcard matching was broken between
//   Next.js 15.2.3 and 15.3.3. Upgrading to 15.3.4 fixed the wildcard, but we
//   keep the exact entries as a belt-and-suspenders fallback.
const buildAllowedDevOrigins = (): string[] => {
  const origins: string[] = [
    // Wildcard patterns — work on Next.js 15.3.4+
    '*.localhost',
    '*.trycloudflare.com',
  ];

  // Exact .localhost hostname derived from PROJECT_HOST (e.g. "oldbook.ai")
  const projectHost = process.env.PROJECT_HOST;
  if (projectHost) {
    origins.push(`${projectHost}.localhost`);
  }

  // Exact Cloudflare tunnel hostname (auto-managed by dev.sh / dev.ps1)
  const tunnelUrl = process.env.CLOUDFLARE_TUNNEL_URL;
  if (tunnelUrl) {
    try {
      // Strip the protocol → "analog-utilities-politics-lead.trycloudflare.com"
      origins.push(new URL(tunnelUrl).hostname);
    } catch {
      // Malformed URL — skip, wildcard already covers it
    }
  }

  return origins;
};

const nextConfig: NextConfig = {
  eslint: {
    ignoreDuringBuilds: true,
  },
  images: {
    unoptimized: true,
  },
  typescript: {
    ignoreBuildErrors: true,
  },
  reactStrictMode: false,

  allowedDevOrigins: buildAllowedDevOrigins(),

  async headers() {
    return [
      {
        source: '/nancy',
        headers: [
          { key: 'Cache-Control', value: 'no-store, no-cache, must-revalidate' },
          { key: 'Pragma', value: 'no-cache' },
        ],
      },
      {
        source: '/resources/:path*',
        headers: [
          { key: 'Cache-Control', value: 'no-store, no-cache, must-revalidate' },
        ],
      },
    ];
  },

  webpack: (config, { dev, isServer }) => {
    if (dev && !isServer) {
      // Polling is required on macOS (Podman VM) and Windows (WSL2) because
      // inotify/FSEvents don't fire across the host → VM → container boundary.
      config.watchOptions = {
        poll: 500,
        aggregateTimeout: 300,
        ignored: [
          '**/node_modules/**',
          '**/.next/**',
          '**/public/bookcovers/**',
        ],
      };
    }
    return config;
  },
};

export default withNextIntl(nextConfig);