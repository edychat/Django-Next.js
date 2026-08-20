#!/usr/bin/env bash
# Monitor Docker build progress and detect stuck builds
# Usage: Run this in the background while building: ./monitor-build.sh [container-name-or-id]

set -euo pipefail

CONTAINER=${1:-}
CHECK_INTERVAL=${CHECK_INTERVAL:-30}  # seconds
STUCK_THRESHOLD=${STUCK_THRESHOLD:-300}  # 5 minutes without output = stuck

if [ -z "$CONTAINER" ]; then
  echo "Usage: $0 <container-name-or-id>"
  echo "  or set CONTAINER env var"
  exit 1
fi

echo "👀 Monitoring build progress for container: $CONTAINER"
echo "   Check interval: ${CHECK_INTERVAL}s"
echo "   Stuck threshold: ${STUCK_THRESHOLD}s"

LAST_OUTPUT=""
LAST_CHANGE_TIME=$(date +%s)

while true; do
  sleep "$CHECK_INTERVAL"
  
  # Get current logs
  CURRENT_OUTPUT=$(podman logs "$CONTAINER" 2>&1 | tail -n 20 || echo "CONTAINER_NOT_FOUND")
  
  if echo "$CURRENT_OUTPUT" | grep -q "CONTAINER_NOT_FOUND"; then
    echo "⚠️  Container not found or exited"
    exit 0
  fi
  
  # Check if output changed
  if [ "$CURRENT_OUTPUT" != "$LAST_OUTPUT" ]; then
    LAST_OUTPUT="$CURRENT_OUTPUT"
    LAST_CHANGE_TIME=$(date +%s)
    echo "✓ [$(date +%H:%M:%S)] Build progressing..."
  else
    # No change detected
    ELAPSED=$(($(date +%s) - LAST_CHANGE_TIME))
    echo "⏱️  [$(date +%H:%M:%S)] No new output for ${ELAPSED}s"
    
    if [ $ELAPSED -gt $STUCK_THRESHOLD ]; then
      echo "❌ BUILD APPEARS STUCK! No output for ${ELAPSED}s"
      echo "Last output:"
      echo "$CURRENT_OUTPUT"
      echo ""
      echo "Suggestions:"
      echo "  1. Kill the container: podman kill $CONTAINER"
      echo "  2. Rebuild with --no-cache: podman build --no-cache ..."
      echo "  3. Check network connectivity"
      echo "  4. Reduce concurrent npm installs"
      exit 1
    fi
  fi
done
