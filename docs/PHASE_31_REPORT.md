# Phase 3.1 implementation report

The existing world, routes, shelter admission, camera and Director interface are preserved. The existing first civilian (A005 in the current scenario) is selected deterministically. Nineteen other agents retain their rule provider. Private observations reuse the existing belief, memory and rumor systems. Inference is serialized, asynchronous from Godot, bounded to one retry and validated twice before intentions are applied.

Created: `ai_service/main.py`, `ai_service/schemas.py`, `ai_service/requirements.txt`, `ai_service/README.md`, `tests/test_phase31_real.gd`, this report, and a local `.venv`.

Adapted existing Phase 3 work: `ai_service/contracts.py`, `engine.py`, `provider.py`, `server.py`; `scripts/agent_observation.gd`, `llm_actions.gd`, `llm_bridge.gd`, `simulation_manager.gd`, `object_inspector.gd`; `resources/ai_config.json`; `.env.example`, `.gitignore`, root `requirements.txt` and `README.md`; `tools/start_ai.cmd`, `start_ai.ps1`, `check_ollama.ps1`; `tests/test_ai_service.py`, `test_phase3.gd`, `test_phase3_http.gd`, `run_phase3_http.py`, `test_phase26.gd`. Existing uncommitted changes were preserved. No agent duplicates or world rebuild were introduced.

Startup commands and beginner troubleshooting are in `ai_service/README.md`.

Executed checks:

- Python unittest discovery: 18 tests, zero failures. Includes FastAPI health and decisions, schema rejection, one retry maximum, prompt privacy, model availability and serialization.
- Godot Phase 3: 17 checks, zero failures. One selected civilian, nineteen rule agents, hidden-state invariance, valid movement, local messages and reset isolation.
- Godot HTTP transport: 11 checks, zero failures. Clock progression during inference, applied movement, pause, reset and timeout fallback. Uses a clearly labeled scripted test provider.
- Real local Ollama health and model check passed. Real `/decide` request returned a validated shelter decision. Real Godot integration applied both COMMUNICATE and MOVE_TO_SHELTER decisions to A005 during separate runs. These are actual model results, not scripted transport output.
- Existing regressions: Phase 1 1436 checks, Phase 2 253 checks, Phase 2.5 1093 checks, Phase 2.6 427 checks; all zero failures. The rendering regression disables AI explicitly to compare deterministic original rules; the separate real integration test covers AI.
- `git diff --check` passed.

Limits: tiny-model explanations may be terse, and targets may be invalid. Such output retries once and then falls back. Confidence is model self-report, not calibrated probability. A test-library deprecation warning is nonfatal. Ollama itself was not deliberately stopped; disconnected and timeout paths were exercised through controlled tests. Human inspection of the running GUI was not performed. No claim of guaranteed evacuation quality is made.

Logs: Godot run JSON includes behavior applications, messages, targets, latency, tokens and fallback. Backend per-run JSONL records inference attempts and invalid output, including failures that cannot return token metadata to Godot.

Phase 3.2: evaluate decision quality over repeated runs, tune prompts and memory relevance, improve social behavior and confidence interpretation. Kafka, multiple LLM agents and ten-day shelter survival remain out of scope.
