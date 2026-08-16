# Preserve Aiden production-3.75 wholesale; replace only the two DeepSeek-V4
# prompt-encoder modules with the official 0731 reasoning-effort semantics.
FROM aidendle94/sparkrun-vllm-ds4-gb10:production-3.75
COPY deepseek_v4.py /opt/venv/lib/python3.12/site-packages/vllm/tokenizers/deepseek_v4.py
COPY deepseek_v4_encoding.py /opt/venv/lib/python3.12/site-packages/vllm/tokenizers/deepseek_v4_encoding.py
