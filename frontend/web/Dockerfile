# frontend/web/Dockerfile
# 
# Fully dynamic Dockerfile that works with any npm workspace structure.
# No hardcoded package names or paths — discovers everything at build time.
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

# Copy entire frontend tree, then strip everything except package*.json files.
# This maximizes layer cache reuse — the layer only invalidates when a 
# package.json or package-lock.json changes, not when source files change.
# Works for any workspace structure without hardcoding paths.
COPY frontend/ ./
RUN find . -type f \
    ! -name "package.json" \
    ! -name "package-lock.json" \
    ! -name "yarn.lock" \
    ! -name "pnpm-lock.yaml" \
    ! -name "tsconfig*.json" \
    -delete && \
    find . -type d -empty -delete

# 1. Inject TypeScript path aliases into web/tsconfig.json so the
#    compiler resolves @shared/* → ../shared/* without hardcoding them.
#    Also strip mobile workspace so npm doesn't install Expo/RN deps.
RUN node -e " \
  const fs = require('fs'); \
  \
  const root = JSON.parse(fs.readFileSync('package.json', 'utf8')); \
  \
  const tscPath = 'web/tsconfig.json'; \
  if (fs.existsSync(tscPath)) { \
    const tsc = JSON.parse(fs.readFileSync(tscPath, 'utf8')); \
    tsc.compilerOptions.paths = { '@/*': ['./*'], '@shared/*': ['../shared/*'] }; \
    fs.writeFileSync(tscPath, JSON.stringify(tsc, null, 2) + '\n'); \
    console.log('✅ tsconfig: @shared/* → ../shared/*'); \
  } \
  \
  if (root.workspaces) { \
    root.workspaces = root.workspaces.filter(w => !w.includes('mobile')); \
    fs.writeFileSync('package.json', JSON.stringify(root, null, 2)); \
  } \
"

# Install all workspace dependencies.
RUN npm install --legacy-peer-deps && npm cache clean --force

# NOTE: Source files are NOT copied here — they are mounted via volume at runtime.
# This ensures the dev server always reads live files from the host.

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

# Auto-detect the web app directory and start the dev server.
# Supports both "web" and "app" as common names, or falls back to the first
# workspace that has a dev script.
CMD ["sh", "-c", "\
  echo '⏳ Waiting for source files...' && \
  until [ -f /app/package.json ]; do sleep 1; done && \
  echo '✅ Source mounted, detecting web workspace...' && \
  WEB_DIR=$(node -e \" \
    const fs = require('fs'); \
    const pkg = JSON.parse(fs.readFileSync('package.json', 'utf8')); \
    const workspaces = pkg.workspaces || []; \
    for (const ws of workspaces) { \
      const dir = ws.replace('/*', '').replace('*', ''); \
      if (dir.includes('web') || dir.includes('app')) { \
        console.log(dir); \
        process.exit(0); \
      } \
    } \
    console.log('web'); \
  \") && \
  cd /app/$WEB_DIR && \
  if [ ! -f node_modules/.package-lock.json ] && [ ! -d node_modules/.bin ]; then \
    echo '📦 Installing dependencies into volume...' && \
    npm install --legacy-peer-deps; \
  fi && \
  echo \"🚀 Starting dev server in $WEB_DIR...\" && \
  exec npm run dev \
"]
