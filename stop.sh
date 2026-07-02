#!/bin/bash
# Stop DS4F-DSpark-Aiden on BOTH nodes.
# Run from Cave. Order doesn't matter — just stops everything.
#
# Usage:
#   ./stop.sh

set -euo pipefail

FORCE_SSH="xraan@192.168.1.88"
CONTAINER="ds4-dspark"

echo "[DS4F-DSpark-Aiden] Stopping on both nodes..."

# Stop worker
echo "  → DragonForce..."
ssh "$FORCE_SSH" "docker rm -f $CONTAINER 2>/dev/null" && echo "    Worker stopped." || echo "    Worker: no running container."

# Stop head
echo "  → DragonCave..."
docker rm -f "$CONTAINER" 2>/dev/null && echo "    Head stopped." || echo "    Head: no running container."

echo ""
echo "[DS4F-DSpark-Aiden] Both nodes stopped."
