#!/bin/bash
# =============================================================================
# apply-encoder-patch.sh — DeepSeek-V4 0731 reasoning-effort encoder fix
# =============================================================================
# The Aiden production-3.75 image ships a prompt encoder where
# reasoning_effort "high" silently injects NO effort prefix (only "max" did).
# The official 0731 GA encoder restores the three-level table:
#   low  → no prefix (default)
#   high → "Absolute maximum..." prompt
#   max  → "Beyond maximum..." prompt
#
# The prebuilt image aidendle94/sparkrun-vllm-ds4-gb10:production-3.75-reffix-0731
# already contains this fix. Use this script only if you want to build it
# yourself or patch an already-running container.
#
# Usage:
#   ./apply-encoder-patch.sh build [TAG]   # build patched image from base 3.75
#   ./apply-encoder-patch.sh patch [NAME]  # patch a RUNNING container in place
#
# Examples:
#   ./apply-encoder-patch.sh build aidendle94/sparkrun-vllm-ds4-gb10:production-3.75-reffix-0731
#   ./apply-encoder-patch.sh patch ds4-dspark
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_IMAGE="aidendle94/sparkrun-vllm-ds4-gb10:production-3.75"
ENCODER_DIR="/opt/venv/lib/python3.12/site-packages/vllm/tokenizers"
FILES=("deepseek_v4.py" "deepseek_v4_encoding.py")

MODE="${1:-}"
case "$MODE" in
  build)
    TAG="${2:-aidendle94/sparkrun-vllm-ds4-gb10:production-3.75-reffix-0731}"
    echo "[encoder-patch] Building ${TAG} from ${BASE_IMAGE}..."
    docker build -t "$TAG" -f "$SCRIPT_DIR/Dockerfile" "$SCRIPT_DIR"
    echo "[encoder-patch] Done. Verify with:"
    echo "  docker run --rm --entrypoint sh $TAG -c 'grep REASONING_EFFORT_PROMPTS $ENCODER_DIR/deepseek_v4_encoding.py'"
    ;;
  patch)
    NAME="${2:-ds4-dspark}"
    echo "[encoder-patch] Patching running container ${NAME}..."
    for f in "${FILES[@]}"; do
      docker cp "$SCRIPT_DIR/$f" "$NAME:$ENCODER_DIR/$f"
      echo "[encoder-patch]   copied $f"
    done
    echo "[encoder-patch] Restarting container to load the new encoder..."
    docker restart "$NAME"
    echo "[encoder-patch] Done. Verify with:"
    echo "  docker exec $NAME grep REASONING_EFFORT_PROMPTS $ENCODER_DIR/deepseek_v4_encoding.py"
    ;;
  *)
    echo "Usage: $0 {build [TAG] | patch [CONTAINER]}"
    echo ""
    echo "  build [TAG]  — build a patched image from ${BASE_IMAGE}"
    echo "  patch [NAME] — copy the fixed encoder into a RUNNING container and restart it"
    exit 1
    ;;
esac
