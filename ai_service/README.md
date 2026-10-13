# Local Llama AI service

Run these commands in PowerShell from the ESSAIM folder:

```powershell
py -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r ai_service/requirements.txt
Copy-Item .env.example .env
ollama list
Invoke-RestMethod http://127.0.0.1:11434/api/tags
.\.venv\Scripts\python.exe -m uvicorn ai_service.main:app --host 127.0.0.1 --port 8765
```

Or double-click `tools/start_ai.cmd`. The script installs Python dependencies and starts only the AI service. Ollama must already be running. No model is downloaded automatically. Check `http://127.0.0.1:8765/health` in your browser.

Open `project.godot` in Godot 4.7, press F5, Start simulation, then Launch nuke. All 150 agents, including authorities, are configured LOCAL_LLM. Select any agent in Director Mode. The inspector shows latest action, explanation, confidence, latency, memories and fallback; the AI label shows connectivity and queue length.

`.env` configures the model, Ollama URL, context, temperature, tokens and timeout. `resources/ai_config.json` configures enablement, LLM agent count (currently 150; zero disables), service URL, decision interval and Godot timeout. Use one uvicorn worker to preserve the shared inference lock.

GET /health reports service, Ollama and model status. POST /decide accepts private agent observations. /v1/decision is a compatibility alias. S5 remains an uncertain public rumor until observed. The model returns intentions; Godot validates and applies them through existing routes, beliefs and communication. Shelter admission remains unchanged.

Logs are saved under `outputs/ai_runs/<run_id>.json`: decisions, targets, messages, fallbacks, latency and reported tokens. Backend /health metrics include invalid responses. Godot calls count HTTP requests; retries are separate inference attempts in backend metrics.

Backend attempt and invalid-output records are saved per run in `outputs/ai_backend_runs/*.jsonl` (hashed filenames; each record includes the original run ID). Backend failure records cover malformed output even when HTTP returns an error. One structured-output retry shares the original inference deadline.

Troubleshooting: DISCONNECTED means check Ollama and port 8765. MODEL_UNAVAILABLE means check `ollama list` for llama3.2:1b. Slow or malformed decisions fall back to rules. Increase both timeouts if needed. Ctrl+C stops the service; simulation rules continue. Setup never downloads another model.

Tests: run `.\.venv\Scripts\python.exe -m unittest discover -s tests`. Godot tests are in `tests/test_phase3.gd` and `tests/test_phase3_http.gd`; invoke the latter through `python -m tests.run_phase3_http --godot <Godot executable>`. With the real service running, launch Godot headless with `--path . --script res://tests/test_phase31_real.gd`.

Phase 3.2: improve tiny-model decision quality and memory relevance, then assess broader social behavior. All-agent inference is now enabled; see `docs/POPULATION_AI.md` for queue behavior and throughput limits. Kafka and shelter survival remain deferred.
