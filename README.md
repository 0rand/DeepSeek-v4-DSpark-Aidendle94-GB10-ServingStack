# DS4F-DSpark-Aiden — production-3.5

DeepSeek-V4-Flash-DSpark on 2x DGX Spark (TP=2 over RoCE).
Recipe by Aiden (aidendle94) — adapted for the Canglong cluster.

## Files

| File | Purpose |
|------|---------|
| `compose.yaml` | Docker Compose service definition (parameterized) |
| `env.cave` | HEAD node env — DragonCave (rank 0) |
| `env.force` | WORKER node env — DragonForce (rank 1) |
| `start.sh` | `./start.sh [cave\|force]` — wrapper for docker compose up |
| `stop.sh` | `./stop.sh` — docker compose down |

## Performance Expectations

- **Single-stream (code)**: ~55–65 tok/s (spec=3), ~65 tok/s (spec=5)
- **Single-stream (prose)**: ~44 tok/s (spec=3), ~48 tok/s (spec=5)
- **Aggregate @ 8 concurrent**: ~145 tok/s
- **Max concurrent**: 128 streams
- **Context window**: 393,216 tokens
- **First boot**: ~15–20 min (kernel compilation + CUDA graph capture)
- **Warm restart**: ~6–7 min (with caches)

## Key Changes from production-v2 (previous Aiden setup)

| What | Old (production-v2) | New (production-3.5) |
|------|---------------------|----------------------|
| **Image** | `aidendle94/sparkrun-vllm-ds4-gb10:production-v2` | `aidendle94/sparkrun-vllm-ds4-gb10:production-3.5` |
| **Model** | Base `DeepSeek-V4-Flash` (specific revision) | `DeepSeek-V4-Flash-DSpark` (draft module baked in) |
| **Spec decode** | MTP, 2 tokens | **DSpark**, 3 tokens (5 for code-heavy) |
| **Context** | 1,048,576 | **393,216** |
| **Max seqs** | 4 | **128** |
| **Batched tokens** | 2048 | **4096** |
| **GID index** | Hardcoded 2 | **Auto-detected** (RoCE v2 + IPv4) |
| **Kernel compile** | No AOT | **VLLM_USE_AOT_COMPILE=1** |
| **Model runner** | V1 | **V2** |
| **New flags** | — | `VLLM_DSPARK_REPLICATE_MARKOV_W1`, `FLASHINFER_SAMPLER`, `BREAKABLE_CUDAGRAPH` |
| **Cache layout** | Single HF mount | **3 dedicated caches** (HF + vLLM + TileLang) |
| **Served name** | `deepseek-v4-flash` | **`deepseek-v4-flash`** (unchanged) |
| **Port** | 8100 | **8100** (unchanged — proxy at :8000 untouched) |
| **shm_size** | 64gb | **32g** |

## Boot Sequence

Order matters. Worker must be listening before the head opens the cross-machine connection.

```bash
# 1. WORKER — DragonForce (rank 1) — start FIRST
ssh dragonforce
cd ~/dockers/DS4F-DSpark-Aiden
./start.sh force

# 2. Wait ~15 seconds

# 3. HEAD — DragonCave (rank 0)
./start.sh cave

# 4. Watch the head logs
docker logs -f ds4-dspark
```

## Verification

```bash
# Health check (from Cave)
curl -s -o /dev/null -w '%{http_code}' http://localhost:8100/health
# Should return 200

# List models
curl -s http://localhost:8100/v1/models

# Chat completion
curl -s http://localhost:8100/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model": "deepseek-v4-flash", "messages": [{"role":"user","content":"Capital of Estonia, one word?"}], "max_tokens": 16, "temperature": 0}'
```

## Tuning Knobs (set in .env)

| Variable | Default | Description |
|----------|---------|-------------|
| `SPEC_TOKENS` | 3 | Speculative tokens. 3=balanced, 5=code-heavy |
| `PORT` | 8100 | API port |
| `GPU_MEMORY_UTILIZATION` | 0.8 | Leave at 0.8 for Spark |
| `MAX_NUM_SEQS` | 128 | Max concurrent requests |
| `GRAPH_CAP` | 128 | Must equal MAX_NUM_SEQS |
| `ASYNC_SCHED` | 1 | Async scheduling (1=on, 0=off) |

**Toggle B12X MoE ↔ Cutlass**: Set `VLLM_USE_B12X_MOE=0` in the environment block of compose.yaml for faster prefill (slower decode).

## Cache Directories

| Mount | Host Path | Contents |
|-------|-----------|----------|
| `/root/.cache/huggingface` | `~/.cache/huggingface` | Model weights (~148 GB) |
| `/cache` | `~/.cache/vllm-ds4-dspark` | Compiled vLLM/attention kernels |
| `/root/.tilelang` | `~/.cache/tilelang-ds4` | DSpark speculative-decode kernels |

Keep all three. Deleting TileLang cache triggers ~25 s kernel recompile on every restart.

## Cluster Network

| Machine | LAN | RoCE | Role |
|---------|-----|------|------|
| DragonCave | 192.168.1.8 | 192.168.0.8 | HEAD (rank 0) |
| DragonForce | 192.168.1.88 | 192.168.0.88 | WORKER (rank 1) |

- **RoCE HCAs**: `rocep1s0f0,roceP2p1s0f0`
- **RoCE netdevs**: `enp1s0f0np0,enP2p1s0f0np0`
- **Control interface**: `enP7s7` (LAN)
- **GID index**: Auto-detected (RoCE v2 + IPv4) — no more hardcoded `2`
