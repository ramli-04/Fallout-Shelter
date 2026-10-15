# Local Llama AI service

Current default: **30 heterogeneous agents**, a shared three-model pool and a
bounded asynchronous scheduler. See [multi-LLM setup and benchmarks](../docs/MULTI_LLM.md).
Scheduling now permits three concurrent requests, one per model. Inspect each
prompt, raw answer and retry at http://127.0.0.1:8765/inspector.
See [the concurrency/inspector guide](../docs/LLM_INSPECTOR.md).
The 120-agent preset requires benchmark opt-in.

## Docker Compose (current startup)

Use [the Docker setup guide](../docs/DOCKER.md). It replaces the removed
tools/start_ai.cmd, start_ai.ps1 and check_ollama.ps1 scripts with containers.
Godot still connects to port 8765. Ollama runs on the internal Docker network.

## Manual Python alternative

Run these commands in PowerShell from the ESSAIM folder if not using Docker:

```powershell
py -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r ai_service/requirements.txt
if (!(Test-Path .env)) { Copy-Item .env.example .env }
ollama list
Invoke-RestMethod http://127.0.0.1:11434/api/tags
.\.venv\Scripts\python.exe -m uvicorn ai_service.main:app --host 127.0.0.1 --port 8765 --workers 1
```

For this manual alternative, Ollama must already be running on Windows. No model is downloaded automatically. Check `http://127.0.0.1:8765/health` in your browser.

Open `project.godot` in Godot 4.7, press F5, Start simulation, then Launch nuke. The default 30 agents, including authorities, are configured LOCAL_LLM across the three model tiers. Select an agent to inspect its model, latest action, explanation, confidence, latency, memories and fallback. Settings contains the Director AI performance dashboard.

`.env` configures pool mode, fallback model, concurrency, Ollama URL and inference settings. `resources/ai_config.json` selects population presets, enablement, assignments and Godot queue/timeouts. Use one Uvicorn worker to preserve the global scheduling limit. Rule-only presets require no backend.

GET /health reports service, Ollama and model status. POST /decide accepts private agent observations. /v1/decision is a compatibility alias. S5 remains an uncertain public rumor until observed. The model returns intentions; Godot validates and applies them through existing routes, beliefs and communication. Shelter admission remains unchanged.

Logs are saved under `outputs/ai_runs/<run_id>.json`: decisions, targets, messages, fallbacks, latency and reported tokens. Backend /health metrics include invalid responses. Godot calls count HTTP requests; retries are separate inference attempts in backend metrics.

Backend attempt and invalid-output records are saved per run in `outputs/ai_backend_runs/*.jsonl` (hashed filenames; each record includes the original run ID). Backend failure records cover malformed output even when HTTP returns an error. One structured-output retry shares the original inference deadline.

Troubleshooting: DISCONNECTED means check Ollama and port 8765. MODEL_UNAVAILABLE means check installed models; DEGRADED can mean only part of the pool is installed. Inspect /health model_status for each tier. Slow or malformed decisions fall back to rules. Ctrl+C stops the service; simulation rules continue. Downloads remain explicit.

Tests: run `.\.venv\Scripts\python.exe -m unittest discover -s tests`. Godot tests are in `tests/test_phase3.gd` and `tests/test_phase3_http.gd`; invoke the latter through `python -m tests.run_phase3_http --godot <Godot executable>`. With the real service running, launch Godot headless with `--path . --script res://tests/test_phase31_real.gd`.

See `docs/MULTI_LLM_PERFORMANCE.md` for measured coverage and tiny-model reliability limits. Immediate blast survival remains Godot-owned. Kafka and ten-day survival remain future work.
