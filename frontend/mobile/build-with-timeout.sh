#!/usr/bin/env bash
# Build helper with timeout and retry logic for mobile Docker builds
# Usage: ./build-with-timeout.sh [build-args...]

set -euo pipefail

BUILD_TIMEOUT=${BUILD_TIMEOUT:-1800}  # 30 minutes default
MAX_RETRIES=${MAX_RETRIES:-2}
RETRY_COUNT=0

echo "🔨 Starting Docker build with timeout protection (${BUILD_TIMEOUT}s)..."

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  echo "📦 Build attempt $((RETRY_COUNT + 1))/$MAX_RETRIES"
  
  if timeout "$BUILD_TIMEOUT" podman build "$@" 2>&1 | tee /tmp/docker-build.log; then
    echo "✅ Build completed successfully!"
    exit 0
  fi
  
  EXIT_CODE=$?
  
  if [ $EXIT_CODE -eq 124 ]; then
    echo "⏰ Build timed out after ${BUILD_TIMEOUT}s"
    RETRY_COUNT=$((RETRY_COUNT + 1))
    
    if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
      echo "🔄 Retrying with --no-cache to avoid stuck layers..."
      # Add --no-cache to the arguments for retry
      set -- "$@" --no-cache
    fi
  else
    echo "❌ Build failed with exit code $EXIT_CODE"
    exit $EXIT_CODE
  fi
done

echo "❌ Build failed after $MAX_RETRIES attempts"
exit 1
