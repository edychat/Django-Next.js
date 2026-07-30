#!/usr/bin/env bash
# Container entrypoint for mobile Metro services.
# Subcommands: start | eas-build
set -euo pipefail

ROOT_DIR="/app"

# ── Patch FallbackWatcher for virtiofs hot reload ─────────────────────────────
_patch_fallback_watcher() {
  local wp="$1/node_modules/metro-file-map/src/watchers/FallbackWatcher.js"
  [ -f "$wp" ] || return 0
  grep -q 'POLLING_PATCH' "$wp" 2>/dev/null && return 0
  echo "🔧 Patching FallbackWatcher ($1)..."
  cat > "$wp" << 'WATCHER_EOF'
// POLLING_PATCH — stat()-based polling for virtiofs/Podman/Docker.
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.default = void 0;
var _AbstractWatcher = require("./AbstractWatcher");
var common = _interopRequireWildcard(require("./common"));
var _fs = _interopRequireDefault(require("fs"));
var _path = _interopRequireDefault(require("path"));
var _walker = _interopRequireDefault(require("walker"));
function _interopRequireDefault(e) { return e && e.__esModule ? e : { default: e }; }
function _interopRequireWildcard(e) {
  if (e && e.__esModule) return e;
  var f = { __proto__: null, default: e };
  if (e != null) for (var k in e) if (k !== 'default' && Object.prototype.hasOwnProperty.call(e, k)) f[k] = e[k];
  return f;
}
const POLL_INTERVAL_MS = 150, DEBOUNCE_MS = 100;
const TOUCH_EVENT = common.TOUCH_EVENT, DELETE_EVENT = common.DELETE_EVENT;
class FallbackWatcher extends _AbstractWatcher.AbstractWatcher {
  #changeTimers = new Map(); #knownFiles = new Map(); #pollTimer = null;
  async startWatching() {
    await new Promise((resolve) => {
      recReaddir(this.root, (_d) => {},
        (f, s) => { this.#knownFiles.set(f, s.mtime.getTime()); },
        (f, s) => { this.#knownFiles.set(f, s.mtime.getTime()); },
        resolve, (err) => { if (!isIgnorableFileError(err)) this.emitError(err); }, this.ignored);
    });
    this.#pollTimer = setInterval(() => this.#poll(), POLL_INTERVAL_MS);
  }
  async #poll() {
    for (const [fp, oldMtime] of this.#knownFiles) {
      try {
        const stat = _fs.default.statSync(fp), newMtime = stat.mtime.getTime();
        if (newMtime !== oldMtime) {
          this.#knownFiles.set(fp, newMtime);
          const type = common.typeFromStat(stat);
          if (type != null) this.#emitEvent({ event: TOUCH_EVENT, relativePath: _path.default.relative(this.root, fp), metadata: { modifiedTime: newMtime, size: stat.size, type } });
        }
      } catch (err) {
        if (isIgnorableFileError(err)) {
          this.#knownFiles.delete(fp);
          this.#emitEvent({ event: DELETE_EVENT, relativePath: _path.default.relative(this.root, fp) });
        }
      }
    }
    try { await this.#scanForNew(this.root); } catch (_) {}
  }
  async #scanForNew(dir) {
    let entries; try { entries = _fs.default.readdirSync(dir, { withFileTypes: true }); } catch (_) { return; }
    for (const e of entries) {
      const fp = _path.default.join(dir, e.name);
      if (this.doIgnore(_path.default.relative(this.root, fp))) continue;
      if (e.isDirectory() && !e.name.startsWith('.') && e.name !== 'node_modules') { await this.#scanForNew(fp); }
      else if ((e.isFile() || e.isSymbolicLink()) && !this.#knownFiles.has(fp)) {
        try {
          const stat = _fs.default.statSync(fp); this.#knownFiles.set(fp, stat.mtime.getTime());
          const type = common.typeFromStat(stat);
          if (type != null) this.#emitEvent({ event: TOUCH_EVENT, relativePath: _path.default.relative(this.root, fp), metadata: { modifiedTime: stat.mtime.getTime(), size: stat.size, type } });
        } catch (_) {}
      }
    }
  }
  async stopWatching() { await super.stopWatching(); if (this.#pollTimer) { clearInterval(this.#pollTimer); this.#pollTimer = null; } }
  #emitEvent(change) {
    const key = change.event + '-' + change.relativePath, existing = this.#changeTimers.get(key);
    if (existing) clearTimeout(existing);
    this.#changeTimers.set(key, setTimeout(() => { this.#changeTimers.delete(key); this.emitFileEvent(change); }, DEBOUNCE_MS));
  }
  getPauseReason() { return null; }
}
exports.default = FallbackWatcher;
function isIgnorableFileError(e) { return e.code === 'ENOENT' || e.code === 'EPERM'; }
function recReaddir(dir, dirCb, fileCb, symlinkCb, endCb, errCb, ignored) {
  const walk = (0, _walker.default)(dir);
  if (ignored) walk.filterDir((d) => !common.posixPathMatchesPattern(ignored, d));
  walk.on('dir', (p, s) => dirCb(_path.default.normalize(p), s))
      .on('file', (p, s) => fileCb(_path.default.normalize(p), s))
      .on('symlink', (p, s) => symlinkCb(_path.default.normalize(p), s))
      .on('error', errCb).on('end', endCb);
}
WATCHER_EOF
  echo "✅ FallbackWatcher patched"
}

# ── start ─────────────────────────────────────────────────────────────────────
cmd_start() {
  echo "🚀 Starting mobile app..."

  SHARED_ASSETS="/app/shared/assets"
  if [ -d "$SHARED_ASSETS" ]; then
    echo "🔗 Setting up @assets symlinks..."
    for app_dir in /app/*/; do
      app_name="$(basename "$app_dir")"
      case "$app_name" in node_modules|shared|scripts|packages|builds) continue ;; esac
      [ -f "$app_dir/package.json" ] || continue
      assets_mod="$app_dir/node_modules/@assets"
      mkdir -p "$assets_mod"
      if [ ! -f "$assets_mod/package.json" ]; then
        echo '{"name":"@assets","version":"1.0.0","main":"index.js"}' > "$assets_mod/package.json"
        echo 'module.exports = {};' > "$assets_mod/index.js"
      fi
      for asset_file in "$SHARED_ASSETS"/*; do
        fname="$(basename "$asset_file")"
        [ ! -e "$assets_mod/$fname" ] && ln -sf "$asset_file" "$assets_mod/$fname"
      done
      echo "  ✅ @assets linked for $app_name"
    done
  fi

  echo "🔄 Syncing app.json files..."
  node - /app << 'NODEEOF'
const fs = require('fs'), path = require('path');
const MOBILE_DIR = process.argv[2] || '/app';
const SKIP = new Set(['node_modules', 'shared', 'scripts', 'packages']);
const toSlug = (n) => n.toLowerCase().replace(/\s+/g, '-');
const toId   = (n) => n.toLowerCase().replace(/\s+/g, '');
const dig    = (obj, ...keys) => keys.reduce((o, k) => (o && o[k] !== undefined ? o[k] : null), obj);
const readAppConfigJs = (appDir) => {
  const p = path.join(appDir, 'app.config.js');
  if (!fs.existsSync(p)) return {};
  try {
    const src = fs.readFileSync(p, 'utf8');
    const pkg = src.match(/package\s*:\s*['"]([\w.]+)['"]/);
    const bid = src.match(/bundleIdentifier\s*:\s*['"]([\w.]+)['"]/);
    return { androidPackage: pkg ? pkg[1] : null, iosBundleId: bid ? bid[1] : null };
  } catch (_) { return {}; }
};
const folders = fs.readdirSync(MOBILE_DIR).filter((name) => {
  if (SKIP.has(name)) return false;
  const dir = path.join(MOBILE_DIR, name);
  try { return fs.statSync(dir).isDirectory() && fs.existsSync(path.join(dir, 'package.json')); } catch (_) { return false; }
});
if (folders.length === 0) { console.log('⚠️  No app folders found'); process.exit(0); }
for (const name of folders) {
  const appDir = path.join(MOBILE_DIR, name), appJson = path.join(appDir, 'app.json');
  const slug = toSlug(name), appConfig = readAppConfigJs(appDir);
  const bundleId = appConfig.androidPackage || appConfig.iosBundleId || ('com.' + toId(name));
  if (fs.existsSync(path.join(appDir, 'app.config.js'))) {
    console.log('⏭️  ' + name + '  (managed — skipping app.json rewrite)'); continue;
  }
  let existing = {}; try { existing = JSON.parse(fs.readFileSync(appJson, 'utf8')); } catch (_) {}
  const projectId = dig(existing, 'expo', 'extra', 'eas', 'projectId') || null;
  const owner = dig(existing, 'expo', 'owner') || null;
  const isBare = fs.existsSync(path.join(appDir, 'android')) || fs.existsSync(path.join(appDir, 'ios'));
  if (!isBare) { console.log('⏭️  ' + name + '  (managed — skipping)'); continue; }
  const fix = (p) => { if (!p) return p; return p.replace(/^\.\.\/\.\.\/packages\/assets\//, '../shared/assets/').replace(/^\.\.\/packages\/assets\//, '../shared/assets/').replace(/^\.\.\/\.\.\/shared\//, '../shared/'); };
  const icon = fix(dig(existing, 'expo', 'icon'));
  const splash = dig(existing, 'expo', 'splash'); if (splash && splash.image) splash.image = fix(splash.image);
  const android = dig(existing, 'expo', 'android'); if (android && android.adaptiveIcon) android.adaptiveIcon.foregroundImage = fix(android.adaptiveIcon.foregroundImage);
  const config = { expo: { name, slug, version: dig(existing, 'expo', 'version') || '1.0.0', runtimeVersion: dig(existing, 'expo', 'runtimeVersion') || '1.0.0', ...(icon ? { icon } : {}), ...(splash ? { splash } : {}), extra: { eas: projectId ? { projectId } : {} }, ...(owner ? { owner } : {}), developmentClient: { silentLaunch: true }, ...(android ? { android } : {}), ...(dig(existing, 'expo', 'ios') ? { ios: dig(existing, 'expo', 'ios') } : {}) } };
  fs.writeFileSync(appJson, JSON.stringify(config, null, 2) + '\n');
  console.log('✅ ' + name + '  →  ' + bundleId + '  (' + slug + ')');
}
NODEEOF

  APP_DIR=""
  for dir in /app/*/; do
    folder="$(basename "$dir")"
    case "$folder" in node_modules|shared|scripts|packages) continue ;; esac
    [ -f "$dir/package.json" ] || continue
    if [ "$(echo "$folder" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')" = "$(echo "${APP_TYPE}" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')" ]; then
      APP_DIR="$dir"; break
    fi
  done

  if [ -z "$APP_DIR" ]; then
    echo "❌ No directory found for APP_TYPE='${APP_TYPE}'"; ls /app | grep -v node_modules; exit 1
  fi

  echo "========================================"; echo "📱 ${APP_TYPE}"; echo "========================================"
  cd "$APP_DIR"
  _patch_fallback_watcher "$APP_DIR"
  _patch_fallback_watcher "/app"

  EXPO_BIN=""
  if   [ -x "./node_modules/.bin/expo" ];                             then EXPO_BIN="./node_modules/.bin/expo"
  elif [ -x "/app/node_modules/.bin/expo" ];                          then EXPO_BIN="/app/node_modules/.bin/expo"
  elif command -v expo-internal >/dev/null 2>&1;                      then EXPO_BIN="expo-internal"
  elif [ -x "/usr/local/lib/node_modules/@expo/cli/build/bin/cli" ]; then EXPO_BIN="node /usr/local/lib/node_modules/@expo/cli/build/bin/cli"
  else EXPO_BIN="npx --yes expo"
  fi

  exec env \
    REACT_NATIVE_PACKAGER_HOSTNAME="${REACT_NATIVE_PACKAGER_HOSTNAME:-localhost}" \
    EXPO_USE_FAST_REFRESH=true EXPO_NO_TELEMETRY=1 \
    $EXPO_BIN start --dev-client --port "${METRO_PORT:-8081}" --host lan
}

# ── eas-build ─────────────────────────────────────────────────────────────────
cmd_eas_build() {
  local _PLATFORM="${PLATFORM:-ios}" _PROFILE="${PROFILE:-development}" _TARGET="${APP:-all}"
  local apps=()
  while IFS= read -r -d '' dir; do
    local name; name=$(basename "$dir")
    [[ "$name" == "node_modules" || "$name" == "shared" ]] && continue
    [[ -f "$dir/package.json" ]] && apps+=("$name")
  done < <(find /app -mindepth 1 -maxdepth 1 -type d -print0)
  [[ ${#apps[@]} -eq 0 ]] && echo "❌ No app directories found" && exit 1
  eas whoami || { echo "❌ EXPO_TOKEN invalid"; exit 1; }
  for folder in "${apps[@]}"; do
    [[ "$_TARGET" != "all" ]] && ! echo "$folder" | grep -qi "$_TARGET" && continue
    echo "📦 EAS build: $folder | platform=$_PLATFORM | profile=$_PROFILE"
    cd "/app/$folder"
    eas build --profile "$_PROFILE" --platform "$_PLATFORM" --non-interactive
    cd /app
  done
  echo "✅ EAS build(s) complete."
}

case "${1:-}" in
  start)     cmd_start ;;
  eas-build) cmd_eas_build ;;
  *) echo "Usage: mobile.sh <start|eas-build>"; exit 1 ;;
esac
