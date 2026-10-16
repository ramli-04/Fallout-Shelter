# Phase 4 measurements

Measured 2026-10-16 UTC. Godot 4.7.2; 30 agents; seed 42; 60 simulated seconds until impact; 5x simulation speed; headless process-loop measurements. These short-horizon screening runs do not measure rendered FPS or establish that reasoning improves evacuation outcomes.

| Preset | Wall s | Process frames/s | Max frame ms | Agents with applied LLM decisions | Applied | Fallback events | Sheltered | Survivors |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| A | 11.84 | 145.0 | 35.1 | 0/30 | 0 | 0 | 1 | 7 |
| B | 11.99 | 144.4 | 51.2 | 0/30 | 0 | 219 | 1 | 7 |
| C | 12.00 | 144.5 | 50.1 | 15/30 | 20 | 168 | 1 | 7 |
| D | 12.00 | 143.4 | 48.2 | 17/30 | 33 | 163 | 1 | 6 |

A = rules; B = shared Llama 1B; C = three local models; D = configured local/cloud groups with cloud disabled. Fallback events include decisions for which no inference was sent. An applied decision passed current-world validation; backend completion alone is insufficient.

## Behavior measurements

| Preset | Shelter choices | Communication receipts | Largest destination fraction |
|---|---|---:|---:|
| A | {"S1": 1, "S2": 4, "S4": 11} | 0 | 0.367 |
| B | {"S1": 1, "S2": 4, "S4": 11} | 0 | 0.367 |
| C | {"S1": 2, "S2": 4, "S4": 11, "S5": 1} | 1 | 0.367 |
| D | {"S1": 4, "S2": 4, "S4": 13} | 0 | 0.433 |

Destination fraction is a consensus proxy. The short horizon may yield few or no contacts and low shelter reachability; these results cannot establish social convergence. Use normal warning duration and repeated seeds for behavioral research.

## Provider and transport checks

The mocked provider test observes 30 overlapping HTTP calls with isolated memories. Real local burst tests admitted at most two calls per local model (six across three models). The installed Ollama configuration may internally serialize work. HTTP overlap is not proof of physical GPU parallelism. Local raw model outputs sometimes fail validation, and capacity rejection deliberately produces immediate fallback rather than an inference backlog.

A real 30-request HTTP/Kafka round trip returned all responses; repeated identity returned the identical cached result. Raw artifacts are in `outputs/phase4/http-benchmark-*.json`. Provider-only bursts are `benchmark-*.json`; Godot comparisons are `godot-[A-D]-seed42.json`. Backend health counters are process-lifetime snapshots and may include preceding runs; Godot `metrics` counters are per run. Do not compare cumulative backend counters as per-run totals.

Local model metadata recorded qwen2.5:0.5b (Q4_K_M), llama3.2:1b (Q8_0), qwen2.5:1.5b (Q4_K_M), Ollama model digests/residency and engine version in provider burst artifacts. A sampled three-model allocation was 3.015 GB. NVIDIA reported 3,474 MiB total GPU use at one sample on a 12,227 MiB RTX 5070 Ti Laptop GPU. Sampling is not a peak allocation guarantee.

No live cloud generation was run, so paid-provider latency, rate limits and actual costs remain unmeasured. Mocked tests cover Gemini, Grok and OpenAI discovery, responses and budgets. No cloud API was enabled and no model was downloaded.

## Limits and follow-up

The first trials exposed synchronous Godot logging stalls; the bridge now writes log files in a worker and polls decision/event HTTP asynchronously. Historical `godot-before-log-fix-*.json` artifacts are diagnostic trials, not the table above. Frame peaks still include OS, filesystem, headless engine and container contention; no real-time rendering SLA is claimed.

Keep 120 disabled until timely agent coverage, invalid outputs, fallbacks and rendered frame times are satisfactory. Increasing population does not require increasing inference admission. Measure longer scenarios and several seeds before drawing performance or behavior conclusions.
