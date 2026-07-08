#!/bin/bash
# Start DS4F-DSpark-Aiden cluster.
#
# ORDER MATTERS: start worker FIRST, wait ~15s, then head.
#
# Usage:
#   ./start.sh               # sync configs to worker, start both
#   ./start.sh head          # HEAD node only (rank 0)
#   ./start.sh worker        # WORKER node only (rank 1)
#   ./start.sh --no-sync     # local only, skip remote sync

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Require .env
[ -f .env ] || { echo "[DS4F-DSpark] Missing .env — copy .env.example to .env and edit"; exit 1; }
set -a; source .env; set +a

# Parse mode
MODE="${1:-both}"
DO_SYNC=true
case "$MODE" in
  head)
    NODE="head"
    ;;
  worker)
    NODE="worker"
    ;;
  --no-sync)
    MODE="both"
    DO_SYNC=false
    ;;
  both)
    ;;
  *)
    echo "Usage: $0 [head|worker|--no-sync]"
    echo ""
    echo "  head       — HEAD node only (rank 0) — start AFTER worker"
    echo "  worker     — WORKER node only (rank 1) — start FIRST"
    echo "  --no-sync  — start both nodes locally, skip remote sync"
    echo "  (default)  — sync configs to worker, then start both"
    exit 1
    ;;
esac

# --- Sync configs to worker ---
sync_worker() {
  echo "[DS4F-DSpark] Syncing configs to worker..."
  ssh "$WORKER_SSH_TARGET" "mkdir -p $WORKER_DIR"
  scp compose.head.yaml compose.worker.yaml .env stop.sh README.md "$WORKER_SSH_TARGET:$WORKER_DIR/"
  ssh "$WORKER_SSH_TARGET" "chmod +x $WORKER_DIR/*.sh"
  echo "[DS4F-DSpark] Sync complete."
}

# --- Start worker ---
start_worker() {
  echo "[DS4F-DSpark] Starting WORKER (rank 1)..."
  ssh "$WORKER_SSH_TARGET" "cd $WORKER_DIR && docker compose --env-file .env -f compose.worker.yaml up -d"
  echo "[DS4F-DSpark] Worker started."
}

# --- Start head ---
start_head() {
  echo "[DS4F-DSpark] Starting HEAD (rank 0)..."
  docker compose --env-file .env -f compose.head.yaml up -d
  echo "[DS4F-DSpark] Head started."
  echo ""
  echo "  Follow logs: docker logs -f ds4-dspark"
  echo "  Health: curl -s -o /dev/null -w '%{http_code}' http://localhost:${PORT:-8100}/health"
}

# --- Execute ---
case "$MODE" in
  both)
    $DO_SYNC && sync_worker
    echo ""
    echo "[DS4F-DSpark] === Launch Sequence ==="
    echo "[DS4F-DSpark] Step 1/2: Starting WORKER..."
    start_worker
    echo "[DS4F-DSpark] Waiting 15s for worker to initialize..."
    sleep 15
    echo "[DS4F-DSpark] Step 2/2: Starting HEAD..."
    start_head
    echo ""
    echo "[DS4F-DSpark] === Both nodes launched ==="
    echo "  First boot: ~15-20 min (kernel compilation + CUDA graph)"
    echo "  Warm restart: ~6-7 min"
    echo ""
    echo "  To stop both:"
    echo "    ssh $WORKER_SSH_TARGET 'cd $WORKER_DIR && ./stop.sh'"
    echo "    ./stop.sh"
    ;;
  head)
    start_head
    ;;
  worker)
    $DO_SYNC && sync_worker
    start_worker
    ;;
esac
