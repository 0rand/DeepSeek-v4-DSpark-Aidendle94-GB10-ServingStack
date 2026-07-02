#!/bin/bash
# Start DS4F-DSpark-Aiden cluster.
#
# ORDER MATTERS: start force FIRST, wait ~15s, then cave.
#
# Usage:
#   ./start.sh               # start both nodes (auto-sync compose+env to Force)
#   ./start.sh cave          # HEAD node only (DragonCave, rank 0)
#   ./start.sh force         # WORKER node only (DragonForce, rank 1)
#   ./start.sh --no-sync     # local only, skip remote sync

set -euo pipefail

cd "$(dirname "$0")"

FORCE_SSH="xraan@192.168.1.88"
FORCE_DIR="~/dockers/DS4F-DSpark-Aiden"

# Determine what to do
MODE="${1:-both}"
DO_SYNC=true
case "$MODE" in
  cave)
    TARGET="cave"
    ;;
  force)
    TARGET="force"
    ;;
  --no-sync)
    MODE="both"
    DO_SYNC=false
    ;;
  both)
    ;;
  *)
    echo "Usage: $0 [cave|force|--no-sync]"
    echo ""
    echo "  cave        — HEAD node only (DragonCave, rank 0) — start AFTER worker"
    echo "  force       — WORKER node only (DragonForce, rank 1) — start FIRST"
    echo "  --no-sync   — start both nodes locally, skip remote sync"
    echo "  (default)   — sync configs to worker, then start both"
    exit 1
    ;;
esac

# --- Sync worker configs ---
sync_worker() {
  echo "[DS4F-DSpark-Aiden] Syncing configs to DragonForce..."
  scp compose.yaml env.force stop.sh README.md "$FORCE_SSH:$FORCE_DIR/"
  ssh "$FORCE_SSH" "chmod +x $FORCE_DIR/*.sh"
  echo "[DS4F-DSpark-Aiden] Sync complete."
}

# --- Start worker ---
start_worker() {
  echo ""
  echo "[DS4F-DSpark-Aiden] Starting WORKER (DragonForce, rank 1)..."
  ssh "$FORCE_SSH" "cd $FORCE_DIR && docker compose --env-file env.force up -d"
  echo "[DS4F-DSpark-Aiden] Worker started."
}

# --- Start head ---
start_head() {
  echo ""
  echo "[DS4F-DSpark-Aiden] Starting HEAD (DragonCave, rank 0)..."
  docker compose --env-file env.cave up -d
  echo "[DS4F-DSpark-Aiden] Head started."
  echo ""
  echo "[DS4F-DSpark-Aiden] Follow logs:"
  echo "  docker logs -f ds4-dspark"
  echo ""
  echo "[DS4F-DSpark-Aiden] Server ready when /health returns 200:"
  echo "  curl -s -o /dev/null -w '%{http_code}' http://localhost:8100/health"
}

# --- Execute ---
case "$MODE" in
  both)
    $DO_SYNC && sync_worker
    echo ""
    echo "[DS4F-DSpark-Aiden] === Launch Sequence ==="
    echo "[DS4F-DSpark-Aiden] Step 1/2: Starting WORKER..."
    start_worker
    echo "[DS4F-DSpark-Aiden] Waiting 15 seconds for worker to initialize..."
    sleep 15
    echo "[DS4F-DSpark-Aiden] Step 2/2: Starting HEAD..."
    start_head
    echo ""
    echo "[DS4F-DSpark-Aiden] === Both nodes launched ==="
    echo "[DS4F-DSpark-Aiden] First boot takes ~15-20 min (kernel compilation + CUDA graph capture)."
    echo "[DS4F-DSpark-Aiden] Restarts with caches: ~6-7 min."
    echo ""
    echo "[DS4F-DSpark-Aiden] To stop both:"
    echo "  ssh dragonforce 'cd ~/dockers/DS4F-DSpark-Aiden && ./stop.sh'"
    echo "  ./stop.sh"
    ;;
  cave)
    start_head
    ;;
  force)
    $DO_SYNC && sync_worker
    start_worker
    ;;
esac
