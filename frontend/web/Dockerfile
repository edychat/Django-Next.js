# frontend/web/Dockerfile
# Works for any project — no workspace detection needed.
# Always installs from frontend/web/package.json directly.
# Source files are volume-mounted at runtime, not copied here.

FROM node:20-alpine

RUN apk add --no-cache curl bash

WORKDIR /app

RUN npm config set registry https://registry.npmjs.org/ && \
    npm config set fetch-retry-mintimeout 20000 && \
    npm config set fetch-retry-maxtimeout 120000 && \
    npm config set fetch-retries 5 && \
    npm config set fetch-timeout 300000

# Copy only the manifest files — invalidates cache only when deps change
COPY frontend/web/package*.json ./

RUN npm install --legacy-peer-deps && npm cache clean --force

ENV NODE_ENV=development \
    HOST=0.0.0.0 \
    PORT=3000 \
    NEXT_TELEMETRY_DISABLED=1 \
    NEXT_PUBLIC_API_URL=http://localhost/api \
    WATCHPACK_POLLING=500 \
    WATCHPACK_POLLING_INTERVAL=500 \
    CHOKIDAR_USEPOLLING=true \
    CHOKIDAR_INTERVAL=500

EXPOSE 3000

CMD ["sh", "-c", "rm -rf /app/.next/cache /app/.next/server /app/.next/static && npm run dev"]
