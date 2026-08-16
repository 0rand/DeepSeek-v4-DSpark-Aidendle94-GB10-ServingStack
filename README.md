# DS4F-DSpark-Aiden

**DeepSeek-V4-Flash-0731 GA** on **2× DGX Spark** (TP=2 over RoCE) at **1M context**.

Recipe by [Aiden (aidendle94)](https://github.com/aidendle94) — upstream image
`aidendle94/sparkrun-vllm-ds4-gb10:production-3.75-reffix-0731`.

This stack serves the **official DeepSeek-V4-Flash-0731** checkpoint (not the
pre-GA DSpark variant) with the official reasoning-effort encoder semantics,
DSpark speculative decoding with a **greedy draft**, and the validated
production tuning from a live 2-node cluster.

---

## What changed vs the pre-GA recipe

| Aspect | Pre-GA | This stack (0731 GA) |
|--------|--------|----------------------|
| Model | `deepseek-ai/DeepSeek-V4-Flash-DSpark` (preview) | `deepseek-ai/DeepSeek-V4-Flash-0731` (official GA) |
| Image | `production-3.7` | `production-3.75-reffix-0731` (encoder fix baked in) |
| Reasoning effort | `high` silently injected **no** prefix | official 3-level ladder (`low`/`high`/`max`) — see [docs/ENCODER-PATCH.md](docs/ENCODER-PATCH.md) |
| Draft sampling | `probabilistic` | `greedy` |
| Generation defaults | temp 0.95 / top_p 0.44 | temp 0.8 / top_p 0.25 / rep 1.0 |
| Context | 524K default | 1M (`MAX_MODEL_LEN=1048576`) |
| Batch / graph | 8192 / 256 | 16384 / 512 |
| Spec tokens | 4 | 5 |

---

## Prerequisites

Two DGX Spark / Gigabyte Atom AI Top nodes (GB10, SM121, 128 GB unified memory
each) with a ConnectX-7 200 Gbps RoCE direct cable (QSFP56), head and worker on
the same RoCE subnet.

- Download the official checkpoint on the head node, then scp it to the worker
  over the RoCE fabric:
  `hf download deepseek-ai/DeepSeek-V4-Flash-0731`
- Pull the image on both nodes:
  `docker pull aidendle94/sparkrun-vllm-ds4-gb10:production-3.75-reffix-0731`
  (or build it yourself — see [Encoder patch](#encoder-patch-0731-reasoning-effort-fix))
- Clone this repo on **both** nodes into the **same absolute path**.

## Quick Start

```bash
# 1. Clone the repo on BOTH nodes
git clone <this-repo> ~/dockers/DS4F-0731-Aiden-3.75

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
| `Dockerfile` | Builds a patched image from base `production-3.75` | No |
| `deepseek_v4.py` / `deepseek_v4_encoding.py` | Official 0731 encoder modules | No |
| `apply-encoder-patch.sh` | Build patched image OR patch a running container | No |
| `docs/ENCODER-PATCH.md` | What the encoder fix changes and why | No |

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

*CAUTION*

The current setup targets maximized KV cache and sits close to the RAM limit at
`GPU_MEMORY_UTILIZATION=0.84`. Depending on your workload (X11, memory-hungry
apps) you may want to limit this to 0.80. If you run no GUI and nothing else on
the Sparks you can try 0.86.

### Cache directories

| Variable | Default | Notes |
|----------|---------|-------|
| `HF_CACHE` | `/home/user/models/deepseek-ai` | Model weights (~148 GB) — must exist before first boot |
| `VLLM_CACHE` | `/home/user/.cache/vllm-ds4-0731-aiden` | Compiled attention/vLLM kernels |
| `TILELANG_CACHE` | `/home/user/.cache/tilelang-ds4-0731-aiden` | DSpark speculative-decode kernels |

Delete the cache dirs to force a full recompile on next boot (~25 min). Keep
them for warm restarts (~6–7 min).

### Model

| Variable | Default | Notes |
|----------|---------|-------|
| `MODEL_PATH` | `deepseek-ai/DeepSeek-V4-Flash-0731` | Official GA repo, or a local path (parent dir of `HF_CACHE` is mounted at `/root/.cache/huggingface`) |
| `MODEL_REVISION` | `7872f01b...` | Pinned commit — prevents cache invalidation on README-only updates |
| `SERVED_MODEL_NAME` | `deepseek-v4-flash` | Name your clients use in `"model"` field — keep stable across config changes |

### Image

| Variable | Default |
|----------|---------|
| `IMAGE` | `aidendle94/sparkrun-vllm-ds4-gb10:production-3.75-reffix-0731` |

### Tuning — validated production profile

| Variable | Default | Description |
|----------|---------|-------------|
| `PORT` | `8100` | API port |
| `TP_SIZE` | `2` | Tensor parallelism (across 2 nodes) |
| `SPEC_TOKENS` | `5` | DSpark speculative tokens (greedy draft) |
| `TEMPERATURE` | `0.8` | Default generation temperature |
| `TOP_P` | `0.25` | Default top-p sampling |
| `REPETITION_PENALTY` | `1.0` | Default repetition penalty |
| `GPU_MEMORY_UTILIZATION` | `0.84` | vLLM GPU memory fraction |
| `MAX_MODEL_LEN` | `1048576` | Context window in tokens (must be multiple of block-size 256) |
| `MAX_NUM_SEQS` | `16` | Max concurrent request slots |
| `MAX_NUM_BATCHED_TOKENS` | `16384` | Tokens per scheduling batch |
| `GRAPH_CAP` | `512` | CUDA graph capture size |
| `ASYNC_SCHED` | `1` | Async scheduling (1=on, 0=off) |

**MoE backend**: the compose files leave `VLLM_USE_B12X_MOE` unset (the image
default). The validated production run uses B12X MoE (`VLLM_USE_B12X_MOE=1`).
To switch to Cutlass MoE, set `VLLM_USE_B12X_MOE: "0"` in the compose files —
note this changes temperature dynamics substantially.

**Draft sampling**: both compose files use `draft_sample_method:"greedy"` in
the DSpark speculative config. The pre-GA recipe used `probabilistic`; greedy
gives more stable, higher acceptance on the GA checkpoint.

---

## Encoder patch — 0731 reasoning-effort fix

The base `production-3.75` image shipped an encoder where
`reasoning_effort:"high"` silently injected **no** effort prefix (only `"max"`
did, and with the wrong text). The official 0731 encoder restores the
three-level ladder. The `reffix-0731` image has this baked in; to build or
patch yourself:

```bash
# Build a patched image from base production-3.75
./apply-encoder-patch.sh build aidendle94/sparkrun-vllm-ds4-gb10:production-3.75-reffix-0731

# Or patch a running container in place
./apply-encoder-patch.sh patch ds4-dspark
```

Full diff and rationale: [docs/ENCODER-PATCH.md](docs/ENCODER-PATCH.md).

### Acceptance note (speculative decoding)

On our cluster, moving from the pre-GA preview checkpoint to the official GA
checkpoint shifted the **speculative acceptance** from ~70–75% down to ~42%
weighted (windows 27.6–80.6%) at identical `k=5`, batch budget, and scheduling.
The actual tool-calling score stayed strong (93/100 on tool-eval-bench, 0%
errors). The two likely causes, in order:

1. The GA draft checkpoint's calibration differs from the preview — same
   architecture and `k` do not guarantee the same draft distribution.
2. The encoder fix changed the effective prompt: callers relying on
   `reasoning_effort` now get the real high/max prefixes, shifting the
   prompt distribution vs the pre-GA silent-high behavior.

This is not a batching regression — batch size, `k`, and scheduling were
unchanged across the comparison. If acceptance matters more than raw speed,
`SPEC_TOKENS=3` is the conservative setting.

---

## QUALITY TESTS

```bash
git clone https://github.com/SeraphimSerapis/tool-eval-bench.git
```

The model likes high temperature, thinks a lot, and explores different
avenues. Default tool-eval-bench settings curtail its abilities, so raise both
max turns and timeout. Our validated run:

```bash
tool-eval-bench --hardmode --seed 42 --parallel 4 --trials 3 --max-turns 30 --timeout 600 \
--backend-kwargs '{"chat_template_kwargs": {"thinking": true, "reasoning_effort": "high","temperature": 1,"top_p":0.25}}'
```

Result on this stack (0731 GA, greedy draft):

```text
Score:        93 / 100
Rating:       ★★★★★ Excellent
Errors:       0%
Mode:         15 short scenarios, parallel 1
Median turn:  2.4 s
```

If your setup can serve at least one 1M-length sequence, **do not reduce**
`MAX_MODEL_LEN`. DeepSeek V4 uses static YaRN configured in the model manifest;
changing the length screws with the scaling factors and vLLM loses its marbles.

---

## Boot Sequence

**Order matters.** The worker must be listening before the head opens the
cross-machine NCCL connection.

```bash
# 1. WORKER (rank 1) — start FIRST
ssh worker-machine
cd ~/dockers/DS4F-0731-Aiden-3.75
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

# List models (serves both deepseek-v4-flash and ds4f-dspark aliases)
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

- **Requires 2× DGX Spark (GB10)** with identical CX7 NIC layout. Single-node
  operation is not supported out of the box.
- **RoCE networking is required** — the NCCL configuration assumes dual-rail
  CX7 InfiniBand over Converged Ethernet.
- **First boot downloads ~148 GB** of model weights from HuggingFace. Ensure
  `HF_HUB_OFFLINE=0` (or comment it out) for the initial download, then set it
  to `1`.
- **The HF cache bug**: If `MODEL_REVISION` points to a commit that only
  changed README.md, the HF Hub may fail with `revision=None` +
  `HF_HUB_OFFLINE=1`. Pin to a content-changing revision. The current default
  is known-good.
- **Container name `ds4-dspark`** is used on both nodes (different hosts, no
  conflict).
- **Reasoning effort**: never send `reasoning_effort:"none"` together with
  `thinking:true` — it forces chat-mode formatting while the reasoning parser
  stays armed, and the whole response lands in `reasoning` with `content:null`.
