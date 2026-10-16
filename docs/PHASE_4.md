# ESSAIM Phase 4

Phase 4 preserves the Godot city and replaces production inference scheduling.
Checkpoint: Git branch `checkpoint/pre-phase4` points to `2ee0cbe`.

## Start the default 30-agent run

From the project folder in PowerShell:

```powershell
docker compose -f compose.yaml -f compose.kafka.yaml -f compose.gpu.yaml up -d --build
```

Omit `-f compose.gpu.yaml` on a machine without NVIDIA container GPU support.
This starts Kafka, Ollama and the Python service. The optional setup profile is
not started: **no models are downloaded automatically**. The three local model
tags were already installed on the development machine. If needed, explicitly run:

```powershell
docker compose exec ollama ollama pull qwen2.5:0.5b
docker compose exec ollama ollama pull llama3.2:1b
docker compose exec ollama ollama pull qwen2.5:1.5b
```

Open `project.godot` in Godot 4, run the main scene, start the city, and launch
the siren. `resources/ai_config.json` defaults to preset `30`: exactly 10 agents
in each group. Seeded role, position, personality, relationships and private
belief generation remain in the existing simulation.

| Group | Default provider | Model |
|---|---|---|
| A | Ollama | qwen2.5:0.5b |
| B | Ollama | llama3.2:1b |
| C | Gemini | GEMINI_MODEL from the backend environment |

Cloud is disabled by default. C therefore uses Godot's rule fallback until
configured, or until its backend configuration is changed to a local provider.
This preserves 30 active simulation agents even with no cloud account.
`config/llm_groups.json` configures providers independently of Godot. Restart
the backend after editing it. The Director settings panel can assign an
individual agent to A/B/C before a run, filter group/agent activity, and show
the actual provider/model on the agent inspector after an applied decision.

Health/metrics: <http://127.0.0.1:8765/health> and `/metrics`.
Private local trace inspector: <http://127.0.0.1:8765/inspector>.

## Execution and Kafka

Each `(run_id, agent_id)` owns a logical actor with independent bounded memory,
latest observation and decision history. Incoming eligible observations create
independent asyncio tasks. A duplicate active request updates the latest state
without creating another inference job. Godot retains its current movement plan;
an agent without a destination receives a rule plan immediately while waiting.

Production dispatch uses `AsyncRuntime`, not the historical threaded `ModelPool`.
There is no application inference FIFO, priority heap or global inference lock.
Admission is immediate: full group capacity produces a fallback instead of a
waiting inference job. Defaults allow two requests per local group and four
cloud group tasks; unavailable cloud tasks do not issue network inference.
`active_requests` / `peak_active_requests` measure actual adapter HTTP calls;
`active` / `peak_active` measure admitted actor tasks. Neither establishes GPU
kernel simultaneity. Ollama's own scheduling and cloud service limits still apply.

With Kafka connected, the path is:

```
Godot HTTP -> decision_requests -> concurrent actor tasks -> decisions -> HTTP
```

Consumers keep polling while other agents reason. Offset commits advance only
past completed records within each partition. Delivery tracking and HTTP waiters
are bounded at 120. There are 30 partitions per topic; this is transport capacity,
not a claim of 30 simultaneous model computations.

Topics are `essaim.agent.observations`, `essaim.agent.decision_requests`,
`essaim.agent.decisions`, `essaim.agent.communications`, `essaim.world.events`,
`essaim.shelter.events`, and `essaim.simulation.metrics`. Events carry a stable
content-derived ID, run ID, correlation ID, UTC timestamp, and agent key where
applicable. The backend creates missing topics but does not resize existing ones.

SQLite claims decision identities before inference and caches completed results.
Replay returns the same result. A crash after claiming may sacrifice that decision
rather than repeat inference. Godot independently rejects repeated applications,
old run IDs, old request IDs, terminal-world results and invalid current targets.
The ledger lives in Docker's `decision_state` volume; Kafka uses `kafka_data`.
Do not delete these volumes when replay protection/durable history is needed.

World/shelter events and range-filtered communication receipts are bridged to
Kafka. Godot remains the authority for physical admission, range, message
recipients, trust updates, relay behavior and action execution. Kafka records are
not broadcast into every agent's mind. This is one authoritative Godot world;
cross-world remote action execution is not implemented.

Inspect durable records without executing them:

```powershell
docker compose -f compose.yaml -f compose.kafka.yaml exec kafka /opt/kafka/bin/kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic essaim.agent.decisions --from-beginning --max-messages 5
```

If Kafka is unavailable at startup or becomes degraded, new requests use direct
local actor dispatch. In-flight bridged requests have a bounded timeout and rule
fallback. Broker reconnection currently requires restarting the backend.
Noncritical Godot telemetry is bounded at 64 concurrent requests and can be
dropped under overload; decision identity records remain in the ledger.

## Cloud configuration and privacy

Use `.env.phase4.example` as a reference. To deliberately enable cloud requests,
set both controls and a model you have access to:

```dotenv
ESSAIM_LOCAL_ONLY=false
ESSAIM_CLOUD_ENABLED=true
GEMINI_MODEL=your-available-flash-model-id
GEMINI_API_KEY=your-key
```

Restart the Compose service with the Kafka overlay. Cloud generation requires
the configured model to be returned by its model-list API. No cloud model name,
price or free usage entitlement is assumed.

For another group/provider, edit its JSON entry. Example OpenAI-compatible entry:

```json
{
  "provider": "openai",
  "model": "${OPENAI_MODEL}",
  "url": "https://api.openai.com/v1",
  "key_env": "OPENAI_API_KEY",
  "concurrency": 2,
  "max_tokens": 128,
  "request_budget": 100,
  "token_budget": 100000
}
```

For xAI use `provider: "grok"`, URL `https://api.x.ai/v1`, key environment
`XAI_API_KEY`, and a configured model. Use `provider: "compatible"` for another
model-list/chat-completions-compatible endpoint. Add custom model environment
variables such as `OPENAI_MODEL` to the Compose service's `environment` mapping;
Compose does not forward arbitrary `.env` variables into containers automatically.
For local Python, the existing `.env` loader makes them available directly.

The adapters use [Gemini model discovery](https://ai.google.dev/api/models),
[OpenAI model discovery](https://developers.openai.com/api/reference/resources/models/methods/list),
and the [xAI compatible chat endpoint](https://docs.x.ai/developers/rest-api-reference/inference/chat-completions).
The last is a compatibility interface; a future xAI Responses adapter can replace
it without changing Godot.

Keys remain backend environment values. They are not included in trace payloads,
Kafka events, health responses or Godot packets. Both local and remote adapters
receive the same nested allowlisted private observation. Hidden impact data,
actual shelter truth, director state and other agents' private memories are not
part of that projection. Local traces intentionally retain agent prompts; keep
them local if simulation data is sensitive.

Request/token budgets apply per configured group adapter for the backend process
lifetime, not as account-wide billing limits. Token reservations conservatively
use prompt UTF-8 bytes plus the maximum output allowance. Set optional
`input_price_per_million` and `output_price_per_million` to obtain estimates;
without prices, `pricing_configured` is false. Account invoices remain authoritative.
Separate groups using the same cloud account must have budgets sized together.
429/5xx responses establish a provider cooldown using Retry-After and exponential
backoff. There is no automatic retry loop; later independent decisions may try
again after cooldown. Restarting resets process budgets.

## Resources and scaling

Context, output token limit, request timeout, keep-alive and concurrency are
configurable per group. Agents share Ollama model weights. `/api/ps` reports
actual residency, allocation, quantization and model digest. The monitor samples
model VRAM, deduplicates allocations reported through the same Ollama URL, and
stops admitting new inference when the sampled allocation exceeds
`AI_MEMORY_BUDGET_GB` (default 10). This cannot prevent every transient allocation.
Optional `nvidia-smi` reports total GPU use where installed; it may be unavailable
inside the Python container even when Ollama has GPU access.

The development GPU reported RTX 5070 Ti Laptop, 12,227 MiB total. A sampled
three-model resident allocation was approximately 3.015 GB; total GPU use was
3,474 MiB at one sample. Qwen models were Q4_K_M; installed Llama 1B was Q8_0.
These samples do not establish a rendering-inclusive peak or a residency guarantee.
Leave room for Godot and the desktop. Increasing contexts or `OLLAMA_NUM_PARALLEL`
changes KV-cache requirements and requires a new measurement.

The optional `120` preset uses 40/40/40 and requires `enable_120: true` in
`ai_config.json`. Keep provider admission limits unchanged initially; increase
population only after checking 30-agent coverage, fallback rate, frame times,
memory and costs. SQLite plus one backend process supports this local design;
multi-host workers need a shared transactional identity store and shared quotas.
Do not start independent hosts with isolated ledgers and assume exactly-once work.

## Experiments and verification

Director presets A/B/C/D reset to the same selected seed. Backend experiment
changes require no active inference. Preset C switches group C to local Qwen 1.5B;
preset D restores the configured C provider. Neither enables cloud billing.

| Preset | Population | Assignment |
|---|---:|---|
| A | 30 | Rule-based |
| B | 30 | All assigned to shared local group B |
| C | 30 | 10/10/10, three local models |
| D | 30 | 10/10/10, configured local/cloud groups |
| 30 | 30 | Default configured groups |
| 120 | 120 | 40/40/40, explicit opt-in |

The provider burst harness is `python -m ai_service.benchmark --preset C` inside
the container; it submits 30 requests at once. A baseline A burst only measures
the harness path, not rule-based simulation performance. The actual Godot clock
benchmark lives in `tests/benchmark_llm_scaling.gd`. Use the same seed, duration,
speed and rendering mode when comparing it. Exports include shelter selections,
communication receipt counts, a largest-destination consensus proxy, evacuation
summary, timely applied decisions, fallbacks, process-loop timing and backend
model metrics. Destination agreement is a proxy, not a validated social consensus
measure. Full completed-run snapshots remain in `outputs/experiment_runs`.

Run automated checks:

```powershell
.\.venv\Scripts\python.exe -m unittest discover -s tests -p 'test_*.py'
godot --headless --path . --script tests/test_phase4.gd
godot --headless --path . --script tests/test_llm_scaling.gd
godot --headless --path . --script tests/test_phase3.gd
godot --headless --path . --script tests/test_warnings.gd
.\.venv\Scripts\python.exe -m tools.benchmark_phase4_http
```

Current automated results: 39 Python tests; Phase 4 12 checks; assignment/scaling
48,319 checks; action validation 17 checks; warnings 68 checks, all passing.
Cloud adapters use mocked transports for discovery, credentials and budget tests.
Live paid cloud generation was not attempted because cloud remained disabled.
The mocked concurrency test observes 30 concurrent calls; real measurements must
be interpreted separately. See `PHASE_4_MEASUREMENTS.md` for measured results.

Historical test limitations: Phase 1 asserts 150 default agents and fails four
population-related assertions with today's 30-agent default. Phase 2 stopped on
a null `.data` access in the test. A broad Phase 3.5 run was stopped after
not completing promptly; the targeted Phase 4 impact checks pass. These historical
suites are not reported as a clean full regression run.

## Files

New: `ai_service/async_providers.py`, `runtime.py`, `events.py`, `benchmark.py`;
`config/llm_groups.json`; `compose.kafka.yaml`; `.env.phase4.example`;
`tests/test_phase4.py`, `tests/test_phase4.gd`; `tools/benchmark_phase4_http.py`, `tools/summarize_phase4.py`;
this guide and the measurements report.

Modified: `.dockerignore`, `Dockerfile`, backend requirements, `ai_service/main.py`,
`contracts.py`, `inspector.py`, backend README; `resources/ai_config.json`;
`scripts/llm_bridge.gd`, `llm_experiments.gd`, `llm_actions.gd`, `rumor_system.gd`,
`simulation_manager.gd`, `main.gd`, `object_inspector.gd`; HTTP test and existing
Godot benchmark; root README. Legacy engines remain for historical tests.
