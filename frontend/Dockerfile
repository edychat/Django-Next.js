# frontend/Dockerfile
FROM node:20-alpine

WORKDIR /app

# Copy package files first for cache-friendly builds
COPY frontend/package*.json ./

# Install dependencies
RUN npm ci --legacy-peer-deps

# Copy app source (after deps for better caching)
COPY frontend/ ./

ENV NODE_ENV=development \
    HOST=0.0.0.0 \
    NEXT_TELEMETRY_DISABLED=1 \
    PORT=3000 \
    NEXT_PUBLIC_API_URL=http://localhost/api

EXPOSE 3000
CMD ["npm", "run", "dev", "--", "--turbopack"]