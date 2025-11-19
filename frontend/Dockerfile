# frontend/Dockerfile
FROM node:20-alpine

WORKDIR /app

# Copy package files first for better caching
COPY frontend/package*.json ./

# Install JS dependencies
RUN npm ci --legacy-peer-deps

# Copy app source
COPY frontend/ ./

# Environment variables
ENV NODE_ENV=development \
    HOST=0.0.0.0 \
    NEXT_TELEMETRY_DISABLED=1 \
    PORT=3000 \
    NEXT_PUBLIC_API_URL=http://localhost/api \
    PRIVATE_ASSETS_PATH=/private_assets \
    WATCHPACK_POLLING=true

EXPOSE 3000
CMD ["npm", "run", "dev", "--", "--turbopack", "-H", "0.0.0.0"]