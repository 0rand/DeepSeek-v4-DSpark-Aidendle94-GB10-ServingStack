# DS4F-DSpark-Aiden

**DeepSeek-V4-Flash-DSpark** on **2× DGX Spark** (TP=2 over RoCE).

Recipe by [Aiden (aidendle94)](https://github.com/aidendle94) — upstream image
`aidendle94/sparkrun-vllm-ds4-gb10:production-3.7`.

---

## Quick Start

```bash
# 1. Clone the repo on BOTH nodes
git clone <this-repo> ~/dockers/DS4F-DFlash-Aiden-3.7

# 2. Configure (one file — edit everything here)
cp .env.example .env
# Edit .env with your IPs, NICs, cache paths, and tuning.

# 3. Launch — worker FIRST, head SECOND
# On the worker node:
docker compose --env-file .env -f compose.worker.yaml up -d

# Wait ~15 seconds, then on the head node:
docker compose --env-file .env -f compose.head.yaml up -d

# Or use the wrapper (syncs configs to worker via SSH, handles ordering):
./start.sh
```

---

## Files

| File | Purpose | Editable? |
|------|---------|-----------|
| `.env.example` | Template — copy to `.env` and edit | — |
| `.env` | **Your cluster config** (gitignored) | **Yes — edit this** |
| `compose.head.yaml` | HEAD node (rank 0) service definition | No — vars come from `.env` |
| `compose.worker.yaml` | WORKER node (rank 1) service definition | No — vars come from `.env` |
| `start.sh` | Wrapper: sync + launch both nodes in order | No (uses `.env` vars) |
| `stop.sh` | Stops containers on both nodes | No (uses `.env` vars) |


---

## Configuration

Everything you need to change lives in **one file: `.env`** (copy from `.env.example`).

### Essential — must change

| Variable | What it is |
|----------|------------|
| `NCCL_IB_HCA` | RoCE HCA names, comma-separated. Find with `ibstat \| grep -E 'CA\|hca_id'` |
| `NCCL_SOCKET_IFNAME` | RoCE netdevs for socket fallback. `ip -br addr` on your RoCE subnet. |
| `CONTROL_IF` | Control-plane netdev (usually one of the above). |
| `MASTER_ADDR` | Head node's RoCE IP address. **Same value on both nodes.** |
| `HEAD_ROCE_IP` | Head node's own RoCE IP (usually same as `MASTER_ADDR`). |
| `WORKER_ROCE_IP` | Worker node's own RoCE IP. |
| `WORKER_SSH_TARGET` | SSH target for the worker (`user@hostname-or-ip`). Used by `start.sh` to sync configs. |
| `WORKER_DIR` | Absolute path to this repo on the worker. |

### Cache directories

| Variable | Default | Notes |
|----------|---------|-------|
| `HF_CACHE` | `/home/user/.cache/huggingface` | Model weights (~148 GB) — must exist before first boot |
| `VLLM_CACHE` | `/home/user/.cache/vllm-ds4-dspark` | Compiled attention/vLLM kernels |
| `TILELANG_CACHE` | `/home/user/.cache/tilelang-ds4` | DSpark speculative-decode kernels |

Delete the cache dirs to force a full recompile on next boot (~25 min). Keep them for warm restarts (~6–7 min).

### Model

| Variable | Default | Notes |
|----------|---------|-------|
| `MODEL_PATH` | `deepseek-ai/DeepSeek-V4-Flash-DSpark` | HuggingFace repo |
| `MODEL_REVISION` | `913f0657...` | Pinned commit — prevents cache invalidation on README-only updates |
| `SERVED_MODEL_NAME` | `deepseek-v4-flash` | Name your clients use in `"model"` field — keep stable across config changes |

### Image

| Variable | Default |
|----------|---------|
| `IMAGE` | `aidendle94/sparkrun-vllm-ds4-gb10:production-3.7` |

### Tuning — validated production profile

| Variable | Default | Description |
|----------|---------|-------------|
| `PORT` | `8100` | API port |
| `TP_SIZE` | `2` | Tensor parallelism (across 2 nodes) |
| `SPEC_TOKENS` | `4` | DSpark speculative tokens. 3=balanced, 5=code-heavy |
| `TEMPERATURE` | `0.95` | Default generation temperature |
| `TOP_P` | `0.44` | Default top-p sampling |
| `GPU_MEMORY_UTILIZATION` | `0.85` | vLLM GPU memory fraction |
| `MAX_MODEL_LEN` | `1048576` | Context window in tokens (must be multiple of block-size 256) |
| `MAX_NUM_SEQS` | `16` | Max concurrent request slots |
| `MAX_NUM_BATCHED_TOKENS` | `8192` | Tokens per scheduling batch |
| `GRAPH_CAP` | `256` | CUDA graph capture size |
| `ASYNC_SCHED` | `1` | Async scheduling (1=on, 0=off) |

**Toggle B12X MoE ↔ Cutlass**: In the compose file, set `VLLM_USE_B12X_MOE: "1"` for B12X MoE (lower prefill latency), or `"0"` for Cutlass MoE (faster decode). Current default: `0` (Cutlass).

---

## Boot Sequence

**Order matters.** The worker must be listening before the head opens the cross-machine NCCL connection.

```bash
# 1. WORKER (rank 1) — start FIRST
ssh worker-machine
cd ~/dockers/DS4F-DFlash-Aiden-3.7
docker compose --env-file .env -f compose.worker.yaml up -d

# 2. Wait ~15 seconds

# 3. HEAD (rank 0) — start SECOND (on head machine)
docker compose --env-file .env -f compose.head.yaml up -d

# 4. Watch the head logs
docker logs -f ds4-dspark
```

Or use the wrapper from the head node:
```bash
./start.sh    # syncs configs to worker, starts worker, waits, starts head
```

### Expected boot times

| Scenario | Time |
|----------|------|
| First boot (no caches) | ~15–20 min (kernel compilation + CUDA graph capture) |
| Warm restart (caches exist) | ~6–7 min |
| Cold with TileLang cache only | ~25 min (kernel recompile) |

---

## Verification

```bash
# Health check (from head node)
curl -s -o /dev/null -w '%{http_code}' http://localhost:8100/health
# Should return 200

# List models
curl -s http://localhost:8100/v1/models

# Chat completion
curl -s http://localhost:8100/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model": "deepseek-v4-flash", "messages": [{"role":"user","content":"Capital of Estonia, one word?"}], "max_tokens": 16, "temperature": 0}'
```

---

## Performance Expectations

| Metric | Value |
|--------|-------|
| Single-stream (code) | ~55–65 tok/s (spec=3), ~65 tok/s (spec=5) |
| Single-stream (prose) | ~44 tok/s (spec=3), ~48 tok/s (spec=5) |
| Aggregate @ 8 concurrent | ~145 tok/s |
| Max concurrent streams | Configured via `MAX_NUM_SEQS` |
| Context window | Configured via `MAX_MODEL_LEN` |

---

## Stopping

```bash
# From the head node — kills both nodes
./stop.sh

# Or manually:
# Worker: ssh worker-machine 'docker rm -f ds4-dspark'
# Head:   docker rm -f ds4-dspark
```

---

## Caveats

- **Requires 2× DGX Spark (GB10)** with identical CX7 NIC layout. Single-node operation is not supported out of the box.
- **RoCE networking is required** — the NCCL configuration assumes dual-rail CX7 InfiniBand over Converged Ethernet.
- **First boot downloads ~148 GB** of model weights from HuggingFace. Ensure `HF_HUB_OFFLINE=0` (or comment it out) for the initial download, then set it to `1`.
- **The HF cache bug**: If `MODEL_REVISION` points to a commit that only changed README.md, the HF Hub may fail with `revision=None` + `HF_HUB_OFFLINE=1`. Pin to a content-changing revision. The current default is known-good.
- **Container name `ds4-dspark`** is used on both nodes (different hosts, no conflict).
