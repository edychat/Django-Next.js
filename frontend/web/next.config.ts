import type { NextConfig } from 'next';

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

  // Allow HMR WebSocket connections from any .localhost subdomain and
  // Cloudflare tunnel hostnames. Required when Next.js sits behind Traefik.
  allowedDevOrigins: [
    '*.localhost',
    '*.trycloudflare.com',
  ],

  webpack: (config, { dev }) => {
    if (dev) {
      // Polling is required on macOS (Podman/Docker VM) and Windows (WSL2)
      // because inotify events don't cross the host→VM→container boundary.
      // poll: 500 = check every 500ms — fast enough to feel instant.
      config.watchOptions = {
        poll: 500,
        aggregateTimeout: 300,
        ignored: ['**/node_modules/**', '**/.next/**'],
      };
    }
    return config;
  },
};

export default nextConfig;
