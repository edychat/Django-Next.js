# frontend/web/Dockerfile
#
# Fully dynamic Dockerfile that works with any npm workspace structure.
# No hardcoded package names or paths — discovers everything at build time.
#
# Supports two layouts automatically:
#   Workspace:  frontend/package.json  (workspaces: ["web", "mobile", ...])
#   Simple:     frontend/web/package.json  (no root package.json)
#
# This file is a shared template — keep it free of project-specific logic.

FROM node:20-alpine

RUN apk add --no-cache curl bash

WORKDIR /app

RUN npm config set registry https://registry.npmjs.org/ && \
    npm config set fetch-retry-mintimeout 20000 && \
    npm config set fetch-retry-maxtimeout 120000 && \
    npm config set fetch-retries 5 && \
    npm config set fetch-timeout 300000

# Copy entire frontend tree, then strip everything except manifest files.
# This maximises layer cache reuse — only invalidates when package files change.
COPY frontend/ ./
RUN find . -type f \
    ! -name "package.json" \
    ! -name "package-lock.json" \
    ! -name "yarn.lock" \
    ! -name "pnpm-lock.yaml" \
    ! -name "tsconfig*.json" \
    -delete && \
    find . -type d -empty -delete

# Detect layout and prepare workspace:
#   - Workspace layout: root package.json exists → strip mobile, patch tsconfig
#   - Simple layout:    no root package.json    → nothing to patch, install from web/
RUN node -e " \
  const fs = require('fs'); \
  const path = require('path'); \
  \
  const rootPkg = 'package.json'; \
  const webPkg  = 'web/package.json'; \
  \
  if (!fs.existsSync(rootPkg)) { \
    console.log('ℹ️  No root package.json — simple layout (web/ only)'); \
    process.exit(0); \
  } \
  \
  const root = JSON.parse(fs.readFileSync(rootPkg, 'utf8')); \
  \
  const tscPath = 'web/tsconfig.json'; \
  if (fs.existsSync(tscPath)) { \
    const tsc = JSON.parse(fs.readFileSync(tscPath, 'utf8')); \
    tsc.compilerOptions = tsc.compilerOptions || {}; \
    tsc.compilerOptions.paths = { '@/*': ['./*'], '@shared/*': ['../shared/*'] }; \
    fs.writeFileSync(tscPath, JSON.stringify(tsc, null, 2) + '\n'); \
    console.log('✅ tsconfig: @shared/* → ../shared/*'); \
  } \
  \
  if (root.workspaces) { \
    root.workspaces = root.workspaces.filter(w => !w.includes('mobile')); \
    fs.writeFileSync(rootPkg, JSON.stringify(root, null, 2)); \
    console.log('✅ Stripped mobile from workspaces'); \
  } \
"

# Install dependencies.
# Workspace layout: install from root (covers all workspaces including web/).
# Simple layout:    install from web/ directly.
RUN if [ -f package.json ]; then \
      echo '📦 Workspace layout — installing from root...' && \
      npm install --legacy-peer-deps && npm cache clean --force; \
    elif [ -f web/package.json ]; then \
      echo '📦 Simple layout — installing from web/...' && \
      cd web && npm install --legacy-peer-deps && npm cache clean --force; \
    else \
      echo '❌ No package.json found'; exit 1; \
    fi

# NOTE: Source files are NOT copied here — mounted via volume at runtime.

ENV NODE_ENV=development \
    HOST=0.0.0.0 \
    NEXT_TELEMETRY_DISABLED=1 \
    PORT=3000 \
    NEXT_PUBLIC_API_URL=http://localhost/api \
    PRIVATE_ASSETS_PATH=/private_assets \
    WATCHPACK_POLLING=true \
    CHOKIDAR_USEPOLLING=true \
    CHOKIDAR_INTERVAL=500 \
    WATCHPACK_POLLING_INTERVAL=500

EXPOSE 3000

# Auto-detect the web directory and start the dev server.
# Workspace layout: root package.json → find workspace named "web" or "app"
# Simple layout:    no root package.json → start directly in /app/web
CMD ["sh", "-c", "\
  echo '⏳ Waiting for source files...' && \
  until [ -f /app/web/package.json ] || [ -f /app/package.json ]; do sleep 1; done && \
  echo '✅ Source mounted' && \
  if [ -f /app/package.json ]; then \
    WEB_DIR=$(node -e \" \
      const fs = require('fs'); \
      const pkg = JSON.parse(fs.readFileSync('package.json', 'utf8')); \
      const ws = pkg.workspaces || []; \
      for (const w of ws) { \
        const d = w.replace('/*','').replace('*',''); \
        if (d.includes('web') || d.includes('app')) { console.log(d); process.exit(0); } \
      } \
      console.log('web'); \
    \"); \
  else \
    WEB_DIR=web; \
  fi && \
  cd /app/$WEB_DIR && \
  if [ ! -d node_modules/.bin ]; then \
    echo '📦 Installing deps into volume...' && \
    npm install --legacy-peer-deps; \
  fi && \
  echo \"🚀 Starting Next.js dev server in $WEB_DIR...\" && \
  exec npm run dev \
"]
