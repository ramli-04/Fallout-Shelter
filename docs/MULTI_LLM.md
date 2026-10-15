# Shared multi-LLM experiments

**Update:** defaults are now three global concurrent requests, one per model.
The serial defaults and measurements below describe the original scaling setup.
Use [LLM_INSPECTOR.md](LLM_INSPECTOR.md) for current configuration, prompt/answer
inspection and concurrent-model verification.

The interactive default is **30 agents**. Godot retains the city, shelters,
sirens, nuclear damage and Director Mode. Ollama owns model instances; Python
uses three shared HTTP clients, never one model instance per person. Memory is
keyed by `(run_id, agent_id)` and survives switching model routes.

| Preset | qwen2.5:0.5b | llama3.2:1b | qwen2.5:1.5b |
|---|---:|---:|---:|
| 30 | 18 | 9 | 3 |
| 120 | 72 | 36 | 12 |

## Installation

For host Ollama (used for the measured benchmarks):

```powershell
ollama pull qwen2.5:0.5b
ollama pull llama3.2:1b
ollama pull qwen2.5:1.5b
ollama list
```

For Docker, install the models in its separate volume. CPU users can omit the
two `-f` options; compatible NVIDIA GPU users can run:

```powershell
docker compose -f compose.yaml -f compose.gpu.yaml up -d ollama
docker compose -f compose.yaml -f compose.gpu.yaml run --rm model-pull pull qwen2.5:0.5b
docker compose -f compose.yaml -f compose.gpu.yaml run --rm model-pull pull llama3.2:1b
docker compose -f compose.yaml -f compose.gpu.yaml run --rm model-pull pull qwen2.5:1.5b
docker compose -f compose.yaml -f compose.gpu.yaml up -d --build ai-service
Invoke-RestMethod http://127.0.0.1:8765/health
```

Open project.godot, F5, Start simulation, Launch nuke. Settings contains
**DIRECTOR / AI PERFORMANCE**: assigned counts, applied decisions, fallbacks,
local/backend queues, active requests, latency, token/decision throughput,
sampled residency, peak model VRAM and unload warnings. Inspectors show each
agent's model tier. For manual Python startup, see ai_service/README.md.

## Presets and reproducibility

resources/ai_config.json controls:

- `experiment_preset`: `30`, `120`, `rules_30`, `rules_120`. `legacy` keeps the
  historical phase1.json population/initialization policy.
- `enabled`: false also disables inference; switching to a normal preset in
  the Director menu explicitly enables it again.
- `enable_120`: false by default. Opt in after reviewing the 30-agent benchmark
  and coverage report. The runner temporarily allows 120 after a measured 30
  run applies at least one decision; it never changes this saved setting.
  This is a functionality gate, not proof of full coverage.
- `model_weights`: `[]` gives exact quotas. Three nonnegative weights such as
  `[6,3,1]` instead use categorical sampling; realized counts may vary. Neither
  policy depends on agent role.
- `max_concurrent_requests`: 1 in-flight HTTP request by default.
- `queue_limit`: 128 waiting requests; `queue_timeout_seconds`: 120 real seconds.
- `decision_interval_seconds`: 12 simulated seconds minimum per agent, not a
  guarantee for the full population.
- HTTP timeout: 30 real seconds; maximum response age: 45 simulated seconds.
  At 5x, responses taking over 9 real seconds become stale.

Independent seeded streams select model tiers, roles and initial priorities.
Existing seeded personalities, beliefs and clear sidewalk slots are retained.
Four authorities are shuffled across agent IDs. Companions, memory, evidence
sources and communication still use the same stable A001/A002 identifiers.
Rule baselines start with the same minds, roles, locations and seed, with
inference disabled. Changing a preset resets the scenario; changing backend
pool mode does not discard existing memories.

The scheduler uses a bounded urgency/arrival-time heap and fixed worker count.
Godot prioritizes missing objectives, rejection, panic and final-minute urgency.
Aging limits starvation. Both layers prevent duplicate run/agent requests.
Observations are created at dispatch, so queue waiting does not age them.
Saturation, expiration, unavailable inference, invalid/stale replies fall back
to rules. Reset rejects old replies; an already-running backend inference can
finish within its timeout and only touches the old run's memory.

## Backend configuration and memory

Copy .env.example to .env only if it does not already exist. Compose forwards:

```dotenv
LLM_CONCURRENCY=1
LLM_QUEUE_LIMIT=128
LLM_QUEUE_TIMEOUT=20
LLM_POOL_MODE=multi
LLM_FALLBACK_MODEL=llama3.2:1b
LLM_AUTO_SINGLE=false
AI_MEMORY_BUDGET_GB=10
OLLAMA_NUM_CTX=2048
OLLAMA_MAX_TOKENS=128
OLLAMA_MAX_LOADED_MODELS=3
OLLAMA_GPU_OVERHEAD=2147483648
LLAMA_ARG_FIT_TARGET=2048
```

Use one Uvicorn worker. For concurrency experiments, change LLM_CONCURRENCY
and Godot max_concurrent_requests together, then measure. Compose sets Ollama
parallelism from LLM_CONCURRENCY. More concurrent contexts require more memory
and do not guarantee more throughput. OLLAMA_MODEL remains a legacy/default
download setting; the pool's allowed tier names are fixed above.

The 10 GB value is a **monitoring budget**, not a hard allocation limit.
OLLAMA_GPU_OVERHEAD and LLAMA_ARG_FIT_TARGET request approximately 2 GiB of
headroom through Ollama's scheduler and newer llama.cpp fitting respectively;
support depends on the runner/version. They do not allocate VRAM for Godot.
See [Ollama environment configuration](https://github.com/ollama/ollama/blob/main/envconfig/config.go).
Host Ollama must be configured separately. Model file size is not resident
model/cache memory.

/health samples [Ollama /api/ps](https://docs.ollama.com/api/ps) for actual
residency, size, size_vram, expiration and context. Unsupported reporting is
marked with residency_error. Sampling can miss brief changes. Three early
disappearances during active work within 120 seconds flag suspected swapping;
ordinary keep-alive expiration counts as an unload without triggering that flag.

Set LLM_POOL_MODE=single to route requests to LLM_FALLBACK_MODEL. With
LLM_AUTO_SINGLE=true, repeated suspected swaps or an exceeded observed budget
switch new requests to single mode. Previously resident models may remain
until Ollama unloads them. Auto switching is off by default for comparability.
Use Godot rules_* presets for baseline experiments without any AI service.

Every tier gets the same compact prompt projection: rounded numeric values,
bounded evidence and memory excerpts. Prompt JSON is capped at 4500 characters
plus bounded system instructions; this is a character limit, not an exact token
count. Full memories/beliefs stay in their existing stores. Responses contain
exactly action, target, message, reason, confidence. One retry shares the
inference deadline. Python and Godot validate responses independently.

## Benchmark commands

```powershell
.\.venv\Scripts\python.exe tools/benchmark_llm_scaling.py --godot "C:\Users\Moham\Downloads\godot\Godot_v4.7.2-stable_win64_console.exe" --speed 5 --render --presets 30 120
.\.venv\Scripts\python.exe tools/benchmark_llm_scaling.py --godot "C:\Users\Moham\Downloads\godot\Godot_v4.7.2-stable_win64_console.exe" --speed 5 --presets rules_30 rules_120
# Use --speed 1 for a five-minute real-time experiment.
```

The runner uses real Ollama and production ModelPool/Engine with a local Python
HTTP adapter; FastAPI transport is tested separately. Reports/screenshots in
outputs/benchmarks record seed, speed, impact deadline, distinct agents with
timely applied decisions, per-model counters, pending work, model digests,
context settings and sampled total GPU usage. Client coverage stops at impact;
a final backend snapshot can include work completed just afterward.

Backend latency includes inference/retries; queue latency is separate. Token
throughput uses Ollama eval_duration, including unsuccessful output attempts.
Decision frequency counts completed decisions per wall second. Godot-applied
decisions and backend-valid intentions are reported separately. Distinct covered
agents are not the same as total decisions. Rule baseline coverage is zero by
definition because no LLM requests are made.

Headless runs exclude rendering. --render includes the actual city/interface;
average process FPS is not a formal frame-time distribution. LLM outputs and OS
scheduling remain nondeterministic even with reproducible initial conditions.
For scientific conclusions, repeat seeds, distinguish cold/warm residency and
hold speed/concurrency constant. Queue coverage never proves simultaneous
120-agent inference. See [the measured report](MULTI_LLM_PERFORMANCE.md).
