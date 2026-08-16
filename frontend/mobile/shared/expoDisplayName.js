/**
 * Helpers for generating consistent Expo identifiers across environments.
 *
 * Used by dev.sh's gen_app_json() and by each app's app.config.js.
 *
 * Usage in app.config.js:
 *
 *   const { getPackageIdentifier, getUrlScheme } = require('../shared/expoDisplayName');
 *
 *   export default {
 *     expo: {
 *       ios:     { bundleIdentifier: getPackageIdentifier('ai.oldbook.app', process.env.EXPO_PUBLIC_ENV) },
 *       android: { package:          getPackageIdentifier('ai.oldbook.app', process.env.EXPO_PUBLIC_ENV) },
 *       scheme:  getUrlScheme('oldbook', process.env.EXPO_PUBLIC_ENV),
 *     },
 *   };
 */

'use strict';

/**
 * Returns the bundle ID / package name for the given environment.
 *   production  → base              (e.g. ai.oldbook.app)
 *   staging     → base.staging      (e.g. ai.oldbook.app.staging)
 *   development → base.development  (e.g. ai.oldbook.app.development)
 *
 * @param {string} base  - Production bundle ID (reverse-DNS, e.g. "ai.oldbook.app")
 * @param {string} [env] - Value of EXPO_PUBLIC_ENV (defaults to "development")
 * @returns {string}
 */
function getPackageIdentifier(base, env) {
  const environment = (env || 'development').toLowerCase();
  if (environment === 'production') return base;
  return `${base}.${environment}`;
}

/**
 * Returns the URL scheme for deep linking.
 *   production  → base            (e.g. oldbook)
 *   otherwise   → base-{env}      (e.g. oldbook-staging, oldbook-development)
 *
 * @param {string} base  - Base scheme without environment suffix
 * @param {string} [env] - Value of EXPO_PUBLIC_ENV
 * @returns {string}
 */
function getUrlScheme(base, env) {
  const environment = (env || 'development').toLowerCase();
  if (environment === 'production') return base;
  return `${base}-${environment}`;
}

/**
 * Returns a human-readable display name with optional environment badge.
 *   production  → base                   (e.g. "OldBook")
 *   otherwise   → base (Env)             (e.g. "OldBook (Dev)")
 *
 * @param {string} base
 * @param {string} [env]
 * @returns {string}
 */
function getExpoDisplayName(base, env) {
  const environment = (env || 'development').toLowerCase();
  if (environment === 'production') return base;
  const badge = environment.charAt(0).toUpperCase() + environment.slice(1);
  return `${base} (${badge})`;
}

module.exports = { getPackageIdentifier, getUrlScheme, getExpoDisplayName };