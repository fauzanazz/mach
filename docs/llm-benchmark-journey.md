# LLM Inference Benchmark Journey

**Date:** 2026-04-22  
**Hardware:** M5 MacBook + RX 6600 (ROCm server via Tailscale)

## The Quest

Started with SD-Turbo image generation, discovered the RX 6600 was slow for img2img due to PCIe memory bandwidth. Pivoted to LLM inference where compute-bound workloads shine.

## Hardware Setup

| System | GPU | VRAM | Backend |
|--------|-----|------|---------|
| M5 MacBook | Apple Silicon | Unified | Ollama + Metal |
| ROCm Server | AMD RX 6600 | 8GB | llama.cpp + ROCm/Vulkan |

**Server Access:** `100.84.28.121` via Tailscale

## Models Tested

| Model | Params | Size | Quantization |
|-------|--------|------|--------------|
| Qwen3 | 8B | 5.2GB | Q4_K_M |
| Gemma 4 | 27B | 7.1GB | e2b Q4_K_M |
| Gemma 4 | 27B | 9.6GB | e4b |

## Endpoints Configured

```bash
# Qwen3 8B (RX 6600 GPU - llama.cpp)
http://100.84.28.121:8081/v1/chat/completions

# Gemma 4 (RX 6600 GPU - llama.cpp)  
http://100.84.28.121:8082/v1/chat/completions

# Gemma 4 (RX 6600 CPU - Ollama) - SLOW, don't use
http://100.84.28.121:11434/api/chat
```

## Benchmark Results

### Speed Comparison (tok/s)

```
Gemma 4 (RX 6600 GPU)  ████████████████████████████████████████████████████  51 tok/s
Qwen3 8B (RX 6600 GPU) ████████████████████████████████████  36 tok/s
Gemma 4 (M5 Metal)     ███████████████████████████████  31 tok/s
Gemma 4 (RX 6600 CPU)  ████  4 tok/s
```

### GraphRAG Extraction (3 queries)

| Model | Backend | Time | Entities | Relationships |
|-------|---------|------|----------|---------------|
| Qwen3 8B | RX 6600 GPU | **25s** | 18 | 17 |
| Gemma 4 | RX 6600 GPU | 51s | 17 | 13 |
| Gemma 4 | M5 Metal | 110s | 17 | 17 |
| Gemma 4 | RX 6600 CPU | 682s | 19 | 18 |

### Key Discovery: Qwen3 Thinking Mode

Qwen3 has a "thinking mode" that generates reasoning tokens before answering. For structured extraction tasks, disable it with `/no_think`:

```
WITH thinking:    87.6s/query, 2022 tokens
WITHOUT thinking: 8.1s/query, 244 tokens  (10.9x faster!)
```

## Quality Comparison

Same extraction task: *"Apple CEO Tim Cook announced the M5 chip at WWDC 2025..."*

### Qwen3 8B Output
```json
{
  "entities": [
    {"name": "Apple", "type": "ORG"},
    {"name": "Tim Cook", "type": "PERSON"},
    {"name": "M5", "type": "PRODUCT"},
    {"name": "WWDC 2025", "type": "EVENT"},
    {"name": "Cupertino", "type": "LOCATION"},
    {"name": "Johnny Srouji", "type": "PERSON"},
    {"name": "TSMC", "type": "ORG"},
    {"name": "Taiwan", "type": "LOCATION"}
  ],
  "relationships": [
    {"source": "Tim Cook", "target": "Apple", "relation": "CEO_OF"},
    {"source": "M5", "target": "Johnny Srouji", "relation": "DESIGNED_BY"},
    {"source": "M5", "target": "TSMC", "relation": "MANUFACTURED_BY"}
  ]
}
```

### Gemma 4 27B Output
```json
{
  "entities": [
    {"name": "Apple", "type": "ORG"},
    {"name": "Tim Cook", "type": "PERSON"},
    {"name": "M5 chip", "type": "PRODUCT"},
    {"name": "WWDC 2025", "type": "EVENT"},
    {"name": "Cupertino", "type": "LOCATION"},
    {"name": "Johnny Srouji", "type": "PERSON"},
    {"name": "TSMC", "type": "ORG"},
    {"name": "Taiwan", "type": "LOCATION"}
  ],
  "relationships": [
    {"source": "Tim Cook", "target": "Apple", "relation": "CEO_OF"},
    {"source": "M5 chip", "target": "Johnny Srouji", "relation": "DESIGNED_BY_TEAM_OF"},
    {"source": "M5 chip", "target": "TSMC", "relation": "MANUFACTURED_BY"}
  ]
}
```

**Quality verdict:** Nearly identical. Gemma 4 slightly more precise ("M5 chip" vs "M5", "DESIGNED_BY_TEAM_OF").

## Recommendations

### For GraphRAG Extraction

| Use Case | Model | Why |
|----------|-------|-----|
| High volume / real-time | **Qwen3 8B + /no_think** | 25s for 3 queries, good quality |
| Quality-critical / batch | **Gemma 4 GPU** | Slightly better precision, 51 tok/s |
| Avoid | Gemma 4 on CPU | 682s is unusable |

### For General Chat

| Use Case | Model | Speed |
|----------|-------|-------|
| Fast responses | Qwen3 8B | 36 tok/s |
| Complex reasoning | Gemma 4 27B | 51 tok/s |

## Lessons Learned

1. **GPU backend matters more than model size** - Gemma 4 on CPU (4 tok/s) vs GPU (51 tok/s) = 12.75x difference

2. **Thinking mode is expensive** - Qwen3's reasoning adds 10x overhead for structured tasks

3. **RX 6600 is great for LLMs** - Unlike img2img where memory bandwidth kills it, LLM inference is compute-bound

4. **M5 Metal is competitive** - 31 tok/s on Gemma 4 27B is impressive for a laptop

5. **Clean JSON output matters** - Qwen3 outputs raw JSON, Gemma wraps in ```json blocks

## Quick Start

```python
import requests

# Fast extraction with Qwen3
resp = requests.post(
    "http://100.84.28.121:8081/v1/chat/completions",
    json={
        "model": "qwen3",
        "messages": [{"role": "user", "content": "/no_think Extract entities as JSON: ..."}]
    }
)
print(resp.json()["choices"][0]["message"]["content"])

# Quality extraction with Gemma 4
resp = requests.post(
    "http://100.84.28.121:8082/v1/chat/completions",
    json={
        "model": "gemma4",
        "messages": [{"role": "user", "content": "Extract entities as JSON: ..."}]
    }
)
print(resp.json()["choices"][0]["message"]["content"])
```

## Server Management

```bash
# SSH to ROCm server
ssh 100.84.28.121

# Check running models
pgrep -a llama-server

# Restart Qwen3 (port 8081)
pkill -f "port 8081"
nohup llama-server -m qwen3-8b-q4.gguf --port 8081 -ngl 99 &

# Restart Gemma 4 (port 8082)
pkill -f "port 8082"
nohup llama-server -m gemma4-e2b.gguf --port 8082 -ngl 99 &
```
