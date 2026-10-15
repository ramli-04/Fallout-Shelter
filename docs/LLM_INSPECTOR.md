# Concurrent models and prompt inspector

The current default is **three concurrent requests globally, one per model**.
The scheduler skips busy model tiers rather than letting them block other tiers.
Godot also dispatches across model tiers. Agents still share the three models;
this does not create a model instance for every agent or run all 120 at once.

| Setting | Default | Location |
|---|---:|---|
| LLM_CONCURRENCY | 3 | .env / Compose / Python pool |
| LLM_PER_MODEL_CONCURRENCY | 1 | .env / Compose / Python pool |
| OLLAMA_NUM_PARALLEL | 1 | .env / Compose Ollama |
| max_concurrent_requests | 3 | resources/ai_config.json |
| per_model_concurrency | 1 | resources/ai_config.json |

OLLAMA_NUM_PARALLEL controls concurrency **within each model** and is now
separate from the global scheduler limit. Three models with one request each
avoid allocating three parallel contexts for every model. Ollama still decides
residency and GPU scheduling; concurrent HTTP requests do not prove simultaneous
GPU kernels or guarantee faster individual answers.

If .env contains older explicit concurrency settings, update them to the values
above. Restart the service after changing settings; restart Godot after editing
its JSON. Keep one Uvicorn worker so the scheduler remains global.

## Docker startup

Install the three models in the Docker volume using the commands in
[MULTI_LLM.md](MULTI_LLM.md), then rebuild/recreate:

```powershell
docker compose -f compose.yaml -f compose.gpu.yaml up -d --build
```

Open **http://127.0.0.1:8765/inspector**, or use **Open LLM prompt inspector** in
Godot Settings. Run the simulation and trigger evacuation to generate decisions.
The base Compose file works on CPU; the GPU override requires supported NVIDIA
Docker GPU access. Close any manual Python service occupying 8765 first.

## What is recorded

Each inference attempt has its own trace ID, model, agent, simulation run,
request ID, retry number and UTC timestamps. Select it to inspect:

- The exact system prompt and compact agent prompt passed to the provider.
- The complete Ollama request payload, including schema and inference options.
- The raw answer string and full Ollama response with token/timing fields.
- Parsed decision, validation errors, timeout/transport errors and latency.

Retries are separate records, including their modified system instructions.
RUNNING means inference has started; VALID means the backend accepted the JSON;
INVALID preserves the rejected answer; ERROR records an inference exception.
INTERRUPTED marks an unfinished attempt recovered after a service restart.
Backend VALID does **not** mean Godot applied the intention: Godot can reject a
late response or changed agent state. Godot acceptance remains in outputs/ai_runs.

The inspector auto-refreshes every two seconds. Filter by model, exact agent ID
or exact run ID, pause refresh, and download a selected record as JSON. Cards
show active requests per model, requests/completions, invalid output/fallbacks,
latency, tokens/s and resident model VRAM. Text is rendered as text, not HTML.

The recent view keeps 300 attempts in bounded memory, restored after restart.
The complete append-only history is stored in:

```text
outputs/ai_backend_runs/inference_traces.jsonl
```

This directory is bind-mounted by Compose. Older records remain in JSONL even
after leaving the recent inspector window. LLM_TRACE_PATH can override the path
for manual runs. A disk write failure is reported in /health and the inspector;
it does not silently disappear or prevent rule fallback.

The inspector shows simulation agents' private prompts to the human Director;
this data is never inserted into other agents' observations. The service remains
bound to localhost on the host via Compose's port mapping.

## Verification

Real Ollama probe on 2026-10-15: three active requests observed, one per model.
Llama 1B and Qwen 1.5B returned HTTP 200; Qwen 0.5B returned HTTP 422 after invalid
output/retry. All five inference attempts were recorded. This used synthetic
PROBE agent observations, not a population coverage benchmark. Results are in
outputs/benchmarks/parallel_probe.json. Reproduce with:

```powershell
.\.venv\Scripts\python.exe tools/check_llm_parallel.py
```

Automated tests cover cross-model overlap, busy-tier skipping, duplicate
suppression, per-model limits, exact prompts, raw invalid answers, retries,
errors, persistence and the inspector API. Godot's parallel transport suite uses
an explicitly TEST_ONLY provider and checks all three models dispatch together.

The [previous performance report](MULTI_LLM_PERFORMANCE.md) used concurrency 1.
Its population coverage figures must not be presented as concurrency-3 results.
