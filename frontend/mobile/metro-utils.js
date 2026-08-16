/**
 * Shared Metro configuration helpers.
 *
 * Centralised here so that all mobile apps stay in sync without duplicating logic.
 */

const fs = require('fs');
const path = require('path');

/**
 * Returns true when Metro is running inside a Docker or Podman container.
 */
function isDocker() {
  return fs.existsSync('/.dockerenv') || fs.existsSync('/run/.containerenv');
}

/**
 * Apply Docker-safe watcher options to a Metro config object.
 * No-op outside Docker so Watchman works normally on the developer's Mac.
 */
function applyDockerWatcherOptions(config) {
  if (isDocker()) {
    config.resolver = { ...config.resolver, useWatchman: false };
    config.watcherOptions = { ...config.watcherOptions, useWatchman: false, poll: 150 };
  }
  return config;
}

/**
 * Wire the @shared/* alias so mobile apps can import shared code from
 * frontend/web/lib/ — the same place the web app reads it from:
 *
 *   import { ApiClient } from '@shared/api-client'
 *   import { theme }     from '@shared/theme'       // now in mobile/lib/
 *
 * Call this from each app's metro.config.js:
 *
 *   const { withSharedAlias } = require('../../metro-utils');
 *   module.exports = withSharedAlias(require('expo/metro-config').getDefaultConfig(__dirname));
 *
 * @param {import('metro-config').MetroConfig} config
 * @param {string} [appDir]  Absolute path to the app directory (defaults to cwd)
 * @returns {import('metro-config').MetroConfig}
 */
function withSharedAlias(config, appDir) {
  const dir = appDir || process.cwd();
  // shared code now lives in frontend/web/lib/
  // frontend/mobile/<app>/ → frontend/web/lib/
  const sharedDir = path.resolve(dir, '../../../web/lib');

  config.resolver = config.resolver || {};
  config.resolver.extraNodeModules = {
    ...config.resolver.extraNodeModules,
    '@shared': sharedDir,
  };

  // Also add web/lib to watchFolders so Metro picks up live changes
  config.watchFolders = [...(config.watchFolders || []), sharedDir];

  return config;
}

module.exports = { isDocker, applyDockerWatcherOptions, withSharedAlias };