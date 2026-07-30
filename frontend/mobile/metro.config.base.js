/**
 * Shared Metro configuration factory for OldBook.ai mobile apps.
 *
 * Usage from each app's metro.config.js:
 *
 *   const createMetroConfig = require('../metro.config.base');
 *   module.exports = createMetroConfig(__dirname, { /* overrides *\/ });
 *
 * Features:
 *  - @shared/* → frontend/web/lib/ alias (shared TS code lives in the web project)
 *  - @assets/* → frontend/web/public/assets/ alias
 *  - Stat-based polling watcher for virtiofs (Docker on macOS)
 *  - FileStore caching
 *  - EAS / production optimisations
 */

'use strict';

const path = require('path');
const fs   = require('fs');

// ── Path helpers ──────────────────────────────────────────────────────────────

/**
 * Resolve the web/lib directory from an app folder.
 * Handles three environments:
 *   1. Host (Mac dev): <repo>/frontend/mobile/<app>/  → <repo>/frontend/web/lib/
 *   2. Docker volume mount: /app/<app>/               → /app/web/lib/
 */
function resolveSharedRoot(appDir) {
  const candidates = [
    // Standard monorepo layout: frontend/mobile/<app>/ → frontend/web/lib/
    path.resolve(appDir, '../../../web/lib'),
    // Docker mount: /app/<app>/ → /app/web/lib/
    path.resolve(appDir, '../../web/lib'),
  ];
  for (const c of candidates) {
    if (fs.existsSync(c)) return c;
  }
  return candidates[0];
}

/**
 * Resolve the web/public/assets directory from an app folder.
 */
function resolveAssetsRoot(appDir) {
  const candidates = [
    path.resolve(appDir, '../../../web/public/assets'),
    path.resolve(appDir, '../../web/public/assets'),
  ];
  for (const c of candidates) {
    if (fs.existsSync(c)) return c;
  }
  return candidates[0];
}

// ── Virtiofs detection ────────────────────────────────────────────────────────

function isDocker() {
  return fs.existsSync('/.dockerenv') || fs.existsSync('/run/.containerenv');
}

// ── Metro config factory ──────────────────────────────────────────────────────

/**
 * @param {string} appDir   - Absolute path to the app directory (__dirname from metro.config.js)
 * @param {object} overrides - Optional Metro config overrides merged on top
 * @returns {import('metro-config').MetroConfig}
 */
function createMetroConfig(appDir, overrides = {}) {
  // Resolve metro config modules from the app's own node_modules first,
  // then fall back to the workspace root. This is critical when metro.config.base.js
  // is volume-mounted at /app/ but the actual metro packages live inside
  // /app/<AppName>/node_modules/ (installed per-app, not at workspace level).
  const { getDefaultConfig } = (() => {
    const resolve = (id) => require(require.resolve(id, { paths: [appDir] }));
    try { return resolve('expo/metro-config'); } catch (_) {}
    try { return resolve('@expo/metro-config'); } catch (_) {}
    try { return resolve('metro-config'); } catch (_) {}
    // Last resort: workspace-level require (may fail in container)
    try { return require('expo/metro-config'); } catch (_) {}
    try { return require('@expo/metro-config'); } catch (_) {}
    return require('metro-config');
  })();

  const config      = getDefaultConfig(appDir);
  const sharedRoot  = resolveSharedRoot(appDir);   // frontend/web/lib/
  const assetsRoot  = resolveAssetsRoot(appDir);   // frontend/web/public/assets/
  const mobileRoot  = path.dirname(appDir);        // frontend/mobile/

  // ── Watch folders ────────────────────────────────────────────────────────
  config.watchFolders = [
    ...(config.watchFolders || []),
    sharedRoot,
    mobileRoot,
  ].filter((v, i, a) => a.indexOf(v) === i);

  // ── Resolver aliases ─────────────────────────────────────────────────────
  config.resolver = config.resolver || {};
  config.resolver.extraNodeModules = {
    ...(config.resolver.extraNodeModules || {}),
    '@shared': sharedRoot,
    '@assets': assetsRoot,
  };

  // Intercept @shared/assets/* requires and return the raw asset path
  const _origResolveRequest = config.resolver.resolveRequest;
  config.resolver.resolveRequest = (context, moduleName, platform) => {
    if (moduleName.startsWith('@shared/assets/')) {
      const assetPath = path.join(assetsRoot, moduleName.slice('@shared/assets/'.length));
      return { type: 'sourceFile', filePath: assetPath };
    }
    if (_origResolveRequest) {
      return _origResolveRequest(context, moduleName, platform);
    }
    return context.resolveRequest(context, moduleName, platform);
  };

  // ── Transformer ──────────────────────────────────────────────────────────
  config.transformer = config.transformer || {};
  config.transformer.getTransformOptions = async () => ({
    transform: {
      experimentalImportSupport: false,
      inlineRequires: true,
    },
  });

  // ── Cache ────────────────────────────────────────────────────────────────
  try {
    const { FileStore } = require(require.resolve('metro-cache', { paths: [appDir] }));
    config.cacheStores = [
      new FileStore({ root: path.join(appDir, '.metro-cache') }),
    ];
  } catch (_) { /* metro-cache may not be installed as a direct dep */ }

  // ── Docker / virtiofs polling watcher ────────────────────────────────────
  if (isDocker()) {
    config.resolver.useWatchman = false;
    config.watcherOptions = {
      ...(config.watcherOptions || {}),
      useWatchman: false,
      poll: 150,
    };
  }

  // ── Merge caller overrides (shallow) ─────────────────────────────────────
  return deepMerge(config, overrides);
}

// ── Utility ───────────────────────────────────────────────────────────────────

function deepMerge(base, override) {
  const out = { ...base };
  for (const [k, v] of Object.entries(override)) {
    if (v && typeof v === 'object' && !Array.isArray(v) && base[k] && typeof base[k] === 'object') {
      out[k] = deepMerge(base[k], v);
    } else {
      out[k] = v;
    }
  }
  return out;
}

module.exports = createMetroConfig;
