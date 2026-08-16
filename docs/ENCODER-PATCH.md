# Encoder Patch — Official 0731 Reasoning-Effort Semantics

## Why

The Aiden `production-3.75` image shipped a prompt encoder with a broken
reasoning-effort ladder:

```python
# OLD (production-3.75)
REASONING_EFFORT_MAX = ("Reasoning Effort: Absolute maximum ...")
assert reasoning_effort in ['max', None, 'high'], ...
if index == 0 and thinking_mode == "thinking" and reasoning_effort == 'max':
    prompt += REASONING_EFFORT_MAX
```

Consequences:
- `reasoning_effort: "high"` was **accepted but silently injected nothing** —
  identical to `low`.
- Only `"max"` produced a prefix, and it used the model's *high* text.
- The three-level ladder (`low` / `high` / `max`) collapsed to two.

The official 0731 GA encoder restores the distinction:

```python
# NEW (official 0731 semantics)
REASONING_EFFORT_PROMPTS: Dict[str, str] = {
    "low":  "",
    "high": ("Reasoning Effort: Absolute maximum with no shortcuts permitted. ..."),
    "max":  ("Reasoning Effort: Beyond maximum — exhaustive, relentless, and uncompromising. ..."),
}
DEFAULT_REASONING_EFFORT = "low"

assert reasoning_effort in REASONING_EFFORT_PROMPTS, ...
if index == 0 and thinking_mode == "thinking":
    prompt += REASONING_EFFORT_PROMPTS[reasoning_effort]
```

And the companion `deepseek_v4.py` normalization:

```python
# OLD
elif reasoning_effort in ("max", "xhigh"):
    reasoning_effort = "max"
else:
    reasoning_effort = "high"          # everything else collapsed to high

# NEW
elif reasoning_effort == "xhigh":
    reasoning_effort = "max"
elif reasoning_effort not in ("low", "high", "max"):
    reasoning_effort = None            # falls through to DEFAULT = low
```

## Why it matters in practice

This is not cosmetic. The encoder change alters the **effective prompt
distribution** for any caller that relies on `reasoning_effort`:

- Callers sending `"high"` previously got the no-prefix (low) prompt. After the
  fix they get the real high-effort instruction — materially stronger.
- Callers sending `"max"` now get DeepSeek's real max text instead of the high
  text.
- `"low"` and omitted stay byte-identical.

On our cluster this showed up as a **speculative-decoding acceptance shift**
(weighted acceptance ~42% vs ~70–75% pre-GA on the same k=5) when the serving
default flipped from the old silent-high to the official high prefix. The
actual tool-calling score stayed strong (93/100 on tool-eval-bench). See
README → *Acceptance note*.

## Files

| File | Role |
|------|------|
| `deepseek_v4_encoding.py` | three-level effort prompt table + injection |
| `deepseek_v4.py` | effort normalization (`xhigh`→`max`, unknown→`low`) |

Both replace the same-named modules under
`/opt/venv/lib/python3.12/site-packages/vllm/tokenizers/` in the image.

## Applying

- **Prebuilt:** `aidendle94/sparkrun-vllm-ds4-gb10:production-3.75-reffix-0731`
  already contains this fix (byte-identical modules).
- **Build yourself:** `./apply-encoder-patch.sh build <tag>` (uses `Dockerfile`).
- **Patch a running container:** `./apply-encoder-patch.sh patch <container>`.

## Verification

```bash
docker run --rm --entrypoint sh <image> -c \
  'grep REASONING_EFFORT_PROMPTS /opt/venv/lib/python3.12/site-packages/vllm/tokenizers/deepseek_v4_encoding.py'
```

Should print the three-level dict.
