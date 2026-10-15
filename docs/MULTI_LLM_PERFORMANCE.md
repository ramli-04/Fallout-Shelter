# ESSAIM multi-LLM performance report

Measured on 2026-10-14 UTC with real local Ollama and the actual Godot city renderer.

Hardware: NVIDIA GeForce RTX 5070 Ti Laptop GPU, 12,227 MiB total VRAM. Godot 4.7.2, OpenGL Compatibility. One global inference request; seed 42; 300 simulated seconds until impact at 5x (about 60 wall seconds). The rendered runs used warm model residency after earlier screening experiments.

| Population | Agents with timely applied decisions | Applied decisions | HTTP requests | Client fallbacks | Mean process FPS | Peak total GPU MiB |
|---|---:|---:|---:|---:|---:|---:|
| 30 | 29/30 | 111 | 137 | 52 | 157.4 | 3510 |
| 120 | 57/120 | 57 | 111 | 107 | 109.1 | 3514 |

A timely decision is a validated intention actually applied by Godot before impact. Distinct agent coverage differs from total decisions. Client fallbacks include rule fallback without an HTTP request; they are not simply HTTP failures. FPS is average process-loop frequency, not a frame-time percentile or rendering SLA.

## Per-model measurements

Counters below are backend deltas per experiment. Successful latency excludes queue wait and failed calls; token throughput includes generated output from failed/retried attempts. Backend completion does not imply Godot accepted the intention.

| Population | Model | Requests | Valid completions | Backend fallbacks | Invalid outputs | Mean successful latency s | Generation tokens/s | Valid decisions/s |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| 30 | qwen2.5:0.5b | 79 | 56 | 23 | 57 | 0.374 | 356.0 | 0.935 |
| 30 | llama3.2:1b | 42 | 42 | 0 | 0 | 0.352 | 239.7 | 0.701 |
| 30 | qwen2.5:1.5b | 17 | 17 | 0 | 0 | 0.433 | 243.5 | 0.284 |
| 120 | qwen2.5:0.5b | 68 | 23 | 45 | 101 | 0.448 | 352.5 | 0.383 |
| 120 | llama3.2:1b | 33 | 31 | 2 | 6 | 0.411 | 236.1 | 0.516 |
| 120 | qwen2.5:1.5b | 11 | 11 | 0 | 1 | 0.388 | 253.5 | 0.183 |

## Memory observations

Ollama reported a sampled model VRAM peak of **3.005 GB**. The three resident allocations were approximately 0.455 GB (Qwen 0.5B), 1.445 GB (Llama 1B) and 1.105 GB (Qwen 1.5B), at a 2048-token context. Qwen tags were Q4_K_M; the installed Llama tag was Q8_0. Peak total GPU usage with rendering was approximately 3.685 GB. These measurements fit the approximate 10 GB target on this machine.

No unloads or suspected swaps were observed during these rendered runs. This does not guarantee all three models remain resident on other hardware or at higher concurrency/context sizes. The budget monitor is not a hard allocator; sampled peaks do not capture every transient allocation. Total GPU usage also includes other GPU users.

## Baselines and interpretation

Rule-only baseline 30: 59.85s wall, 0 LLM requests. These runs were headless; their initial scenario/seed and impact duration match, but their rendering cost does not.

Rule-only baseline 120: 59.90s wall, 0 LLM requests. These runs were headless; their initial scenario/seed and impact duration match, but their rendering cost does not.

The 0.5B tier is the principal structured-output reliability limitation. Its invalid/retry rate was higher at 120 agents in this sample; no causal relationship is established. The system remains operational through rule fallback; these agents must not be described as receiving reliable LLM decisions at every interval. The 1B and 1.5B tiers performed better in this sample.

**Keep 30 as the default and 120 opt-in.** The 120-agent run did not achieve full timely coverage. All runs used concurrency 1; none demonstrate simultaneous 120-agent inference. A single-model route using llama3.2:1b is available for comparison or swapping problems, but no performance claim for that mode is established by these heterogeneous runs.

This is a single-seed screening benchmark, not a statistical population study. Repeat seeds at 1x and 5x, distinguish cold/warm starts, and evaluate decision quality and evacuation outcomes before enabling 120 for a scientific study. Seed reproducibility controls initial conditions, not LLM output determinism. The Python HTTP adapter used the production scheduler/engine; the FastAPI and Docker paths were validated separately.

## Validation

- Python: 24 tests passed, including pool bounds, urgency, duplication, concurrency, timeouts, memory isolation, single-model memory continuity and residency warnings.
- Godot seeded 30/120/baseline suite: 48,319 checks, zero failures.
- Scripted transport tests: 30-agent and 120-agent queues drained with no duplicates; these are TEST_ONLY transport checks, not LLM performance evidence.
- Godot regressions passed for LLM actions/HTTP, seeded social behavior (1323 checks), 3D navigation (617 checks), UI (33 checks), nuclear impact (861 checks) and warnings (68 checks).
- CPU/GPU Compose configurations validated; AI Docker image built successfully; container-to-host Ollama connectivity verified with all three models.

Raw JSON, GPU samples, model digests and traces are available in outputs/benchmarks and outputs/ai_runs. Installation and reproducible commands: [MULTI_LLM.md](MULTI_LLM.md).
