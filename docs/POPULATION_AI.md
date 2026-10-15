# 150 agents with local AI

Historical single-model configuration. Current 30/120 shared model experiments
and startup commands are documented in [MULTI_LLM.md](MULTI_LLM.md).

The current scenario has 150 agents (including the existing four authorities). Every agent has configured provider LOCAL_LLM using the shared llama3.2:1b service. Existing rule decisions remain emergency fallback when service, validation or timeout fails.

Shelter capacities are S1 125, S2 37, S3 90, S4 175, S5 250. Capacities are divided by twenty and rounded down to whole occupants. Public rough capacity estimates and the scoring normalizer use the same scale. Supply quantities and S5's hidden existence remain unchanged.

Additional spawn locations use existing clear sidewalks; the city, roads, navigation and shelter admission are preserved. The Director lists all agents and shows queue and active-request counts, plus each agent's queue status.

The Godot bridge uses a FIFO queue with one active inference request. Each agent has at most one pending or queued request. It observes the agent's current private knowledge at dispatch, so waiting does not age the observation. An agent continues its existing movement while awaiting a new decision; an agent without an initial decision waits. Terminal agents are skipped. Reset cancels and discards queued work. Logging is accumulated incrementally and saved at most once per second, on reset and on exit.

The decision interval is a minimum between requests for a particular agent, not a guarantee that all 150 receive a decision every twelve seconds. One local model serves them sequentially. If an average decision takes two seconds, a full round takes roughly 300 seconds before retries or terminal-agent skips. Faster simulation speeds advance the scenario without increasing model throughput. Start at 1x. The game stays responsive, but some agents can still await their first decision when the evacuation deadline arrives.

Start from the project folder using [Docker Compose](DOCKER.md), then open `project.godot`, press F5, start the simulation and launch the alarm. See `ai_service/README.md` for service configuration. Adjust population in `resources/phase1.json` and AI count in `resources/ai_config.json` together when increasing beyond 150. AI can be disabled for original rule-only behavior.

Verification includes `tests/test_population_ai.gd`, exercised through the scripted HTTP test service:

```powershell
.\.venv\Scripts\python.exe -m tests.run_phase3_http --godot "C:\Users\Moham\Downloads\godot\Godot_v4.7.2-stable_win64_console.exe" --script res://tests/test_population_ai.gd --inference-delay 0.005
```

This test checks real HTTP scheduling and behavior for all 150 agents with a clearly labeled scripted provider; it does not claim to run 150 real model decisions. `tests/test_phase31_real.gd` checks the real model in the current 150-agent scenario.

Previous 220-agent verification: the population HTTP test passed 13,982 checks and applied scripted decisions to all 220 agents. The 3D navigation/rendering regression passed 4,227 checks; the project initialization regression passed 15,236 checks. The existing AI action test passed 17 checks and asynchronous HTTP test passed 11 checks. Python discovery passed 18 tests. Real Ollama inference chose S4 for A001, resulting in MOVING state, in the current 220-agent scenario. A full round of 220 real Ollama decisions was not run.
