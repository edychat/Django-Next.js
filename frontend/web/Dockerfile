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
    # Polling is REQUIRED on macOS (Podman VM) and Windows (WSL2) because
    # inotify/FSEvents don't cross the host→VM→container volume-mount boundary.
    WATCHPACK_POLLING=500 \
    WATCHPACK_POLLING_INTERVAL=500 \
    CHOKIDAR_USEPOLLING=true \
    CHOKIDAR_INTERVAL=500

EXPOSE 3000

# Clear the compiled .next cache before starting so stale chunks from a
# previous container run are never served. The source volume is live-mounted
# from the host, but .next is a named volume that survives container restarts.
CMD ["sh", "-c", "rm -rf /app/.next/cache /app/.next/server /app/.next/static && npm run dev"]
