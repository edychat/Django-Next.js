# frontend/web/Dockerfile
FROM node:20-alpine

RUN apk add --no-cache curl bash

WORKDIR /app

RUN npm config set registry https://registry.npmjs.org/ && \
    npm config set fetch-retry-mintimeout 20000 && \
    npm config set fetch-retry-maxtimeout 120000 && \
    npm config set fetch-retries 5 && \
    npm config set fetch-timeout 300000

COPY frontend/web/package*.json ./

RUN npm install --legacy-peer-deps && npm cache clean --force

ENV NODE_ENV=development \
    HOST=0.0.0.0 \
    PORT=3000 \
    NEXT_TELEMETRY_DISABLED=1 \
    NEXT_PUBLIC_API_URL=http://localhost/api \
    # WATCHPACK_POLLING must be a NUMBER (ms) not "true".
    # "true" silently uses the default 5007ms — far too slow for dev.
    # Works on macOS (Podman VM), Linux, and Windows (WSL2) volume mounts.
    WATCHPACK_POLLING=500 \
    CHOKIDAR_USEPOLLING=true \
    CHOKIDAR_INTERVAL=500

EXPOSE 3000

# Run webpack mode (not turbopack) — turbopack has its own native watcher
# that doesn't work through VM/container volume mounts. Webpack + polling does.
CMD ["npm", "run", "dev"]
