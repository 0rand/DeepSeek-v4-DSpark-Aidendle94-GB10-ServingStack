#!/bin/bash
# Stop DS4F-DSpark-Aiden on BOTH nodes.
# Run from the head node. Order doesn't matter — stops everything.
#
# Usage:
#   ./stop.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

[ -f .env ] || { echo "[DS4F-DSpark] Missing .env — copy .env.example to .env and edit"; exit 1; }
set -a; source .env; set +a

CONTAINER="${CONTAINER_NAME:-ds4-dspark}"

echo "[DS4F-DSpark] Stopping on both nodes..."

# Stop worker
echo "  → Worker..."
ssh "$WORKER_SSH_TARGET" "docker rm -f $CONTAINER 2>/dev/null" && echo "    Worker stopped." || echo "    Worker: no running container."

# Stop head
echo "  → Head..."
docker rm -f "$CONTAINER" 2>/dev/null && echo "    Head stopped." || echo "    Head: no running container."

echo ""
echo "[DS4F-DSpark] Both nodes stopped."
