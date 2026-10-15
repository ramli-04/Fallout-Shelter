# ESSAIM Phase 3: local LLM agents

The existing Godot 4 city, camera, fixed simulation clock, shelters, incidents,
Director tools and rule policy are preserved. Default population: 20 agents,
five configured for LOCAL_LLM and fifteen RULE_BASED. Offline LLM agents use
FALLBACK_RULE_BASED. The production service calls Ollama; it has no scripted AI
provider. Test providers exist only in tests and are explicitly labeled.

## Current Docker startup

Use [Docker Compose](DOCKER.md) instead of the removed start_ai and check_ollama
scripts. The setup below is historical; current settings use 150 agents and
llama3.2:1b. See ai_service/README.md for the manual Python alternative.

## Historical beginner setup on Windows

1. Install Python **3.12** (or 3.11) from https://www.python.org/downloads/ with
   the Python launcher enabled. Confirm `py -3.12 --version`. This workspace
   currently has only Python 3.14; automated Python checks were run on that
   interpreter. The service uses standard-library APIs available in 3.11/3.12.
2. Install Ollama from https://ollama.com/download/windows and start it.
   Default endpoint: `http://127.0.0.1:11434`. `ollama list` shows installed models.
3. Choose a model before downloading. Default `qwen2.5:3b` is a 3.09B Q4_K_M
   model with a roughly 1.9GB download, according to its
   [Ollama model page](https://ollama.com/library/qwen2.5:3b).
   Actual GPU memory also includes runtime/context overhead. No script downloads
   models. **If you choose this model**, manually run `ollama pull qwen2.5:3b`.
4. From the project directory, copy `.env.example` to `.env`. Set OLLAMA_MODEL to
   the exact installed tag. All five LLM agents share it. The optional future
   provider seam is `ai_service/provider.py:Provider`; external APIs are not added.
5. Run the following in PowerShell. No pip dependencies are required;
   `requirements.txt` documents the standard-library setup.

```powershell
Set-Location 'C:\Users\Moham\OneDrive\Desktop\ESSAIM'
Copy-Item .env.example .env  # first setup only; preserve later edits
py -3.12 -m pip install -r requirements.txt
powershell -NoProfile -ExecutionPolicy Bypass -File tools/check_ollama.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools/start_ai.ps1
```

Use `-PythonVersion 3.11` for Python 3.11. The `.cmd` launcher provides a
double-click option and leaves the service in the terminal; Ctrl+C stops it.
Startup checks Ollama and model availability before opening the service port.
It exits clearly if either is missing. No GPU model is loaded by the preflight.

6. Keep the terminal open. Open the existing `project.godot`, press F5, then
   Start simulation and Launch nuke. The AI status under the city heading should
   read CONNECTED. Select an agent to see configured/active provider, model
   explanation, decision history, latency and deviation flags. Decisions begin
   during evacuation; ordinary pre-alarm city behavior remains Phase 2.5 behavior.

## Configuration and laptop performance

`resources/phase1.json` controls total population (20 by default, existing limit
24). `resources/ai_config.json` controls LLM count (5), enable flag, service URL,
health polling, request timeout, LLM interval and response age. Set enabled false
or LLM count zero for rule-only runs. Restart F5 after config edits.

`.env` controls model, Ollama URL, service port, 4096-token context, 256 maximum
generated tokens (provider setting), 30-second inference timeout, 8-second queue
wait and five pending requests. Only one inference runs at once; others wait
briefly or fall back. The model remains loaded for two minutes after activity.
Close other GPU-heavy programs for demonstrations. Start at 1x speed; 10x makes
observations age much faster than inference and can produce stale-response fallback.
There is no separate model per agent and no continuous background generation.
If you change AI_PORT, also change the Godot service_url port.

## Information boundary and memory

Godot generates an observation from one agent's profile, subjective warning time,
current goals/location/destination, private beliefs, memories and known messages.
It adds only publicly visible fields of nearby outdoor people. It does not send
WorldState, shelter truth, stocks, hidden incident schedules, Director state or
exact impact time. Shelter belief positions may include the rumored S5 site.
Nested allowlists in both languages omit internal observation signatures and raw
evidence packets. A directly observed fact may legitimately become a belief.
Existing entrance perception still reveals capacity/occupancy only within the
configured observation radius; it never becomes a global truth feed.

The service maintains a bounded run-ID/agent-ID memory store, current profile,
goals, fears derived from stress, destination, beliefs and source-specific trust.
Recent memory: 12 entries; important events/promises: eight; rolling extractive
summary: 1200 characters. Summaries concatenate older experiences without another
GPU call. Request context is bounded; older/redundant context is trimmed first.
Up to 128 agent/run records are retained in process memory. Reset creates a new
run ID so old memories cannot enter a new run; restart clears all service memory.
There is no disk persistence or vector database. Rumors keep their original source
and speaker; confidence and observation timestamps remain in the private beliefs.

The LLM interprets received conversations within its next decision prompt. Godot
delivers generated speech only to nearby recipients with provenance. Free-form
speech is unverified conversation and does not magically overwrite structured
shelter beliefs. Existing recognized rumors/reports retain their interpretation
rules. Personalities use all 15 existing archetypes and numeric traits; new labels
can be supplied without hardcoded model action scripts.

## Actions and validation

MOVE_TO_SHELTER and CHANGE_DESTINATION plan the existing road route to a known
believed shelter location. FOLLOW_AGENT follows the currently visible person's
shelter destination; it is not continuous pursuit. HELP_AGENT calms a nearby
person and spends the existing help duration. COMMUNICATE sends bounded speech
to one nearby person or broadcasts locally. WAIT and OBSERVE pause temporarily;
OBSERVE refreshes local entrance perception. STAY_HOME pauses in place temporarily
(the simulation has no separate home interiors). These minimal semantics preserve
the existing movement model. Godot checks current targets/range/state before
execution; doors, existence, capacity and admission remain authoritative.

HTTP requests run through threaded HTTPRequest nodes. Movement continues during
inference. Pending requests are canceled at reset; responses check run, agent,
request ID, phase and age. Paused responses are discarded; they cannot move an
agent. Invalid/late/unavailable/overloaded requests fall back to the original
policy and retry later. Physical stress/reaction delay, road blocking and impact
still govern all agents.

## API and evaluation

- `GET /health` and `GET /metrics`: status, shared model and metrics.
- `POST /v1/decision`: schema_version 1, run_id, request_id, observation.
- Response: matching identifiers, provider, decision (action/target/message/reason),
  latency_seconds and deviation_flags. Failures return 422/429/503; no fake model
  decision is returned. Godot performs the rule fallback locally.

Service binds only to 127.0.0.1. CONNECTED means Ollama is reachable and the tag
exists, not proof of a successful inference. DISCONNECTED means the service or
Ollama is unreachable; MODEL_UNAVAILABLE means the tag is absent; DEGRADED means
recent failures, overload or invalid/stale decisions. Health recovers on later
checks and successful decisions. Request/success/failure/busy/token/latency metrics
are cumulative; latency includes queueing. Director Export trace includes agent
providers, decisions and per-agent LLM metrics along with existing world trace.

Deviation flags are transparent exploratory proxies: authority staying home and
cooperative/self-sacrificing withdrawal with nearby people. They are counted but
never force behavior. They are **not** a validated personality fidelity metric;
academic evaluation should review traces and add a justified coding rubric.
LLM runs depend on inference timing/output and are not deterministic seeded replay.
Rule-only runs retain seeded replay. No Kafka or survival/rationing is introduced.
Versioned decision envelopes provide a future transport seam.

## Checks and troubleshooting

```powershell
py -3.12 -m unittest discover -v
& $GodotExe --headless --path . --script res://tests/test_phase3.gd
py -3.12 -m tests.run_phase3_http --godot $GodotExe
py -3.12 -m ai_service.server --check
Invoke-RestMethod http://127.0.0.1:8765/health
```

The HTTP test starts a local TEST_ONLY provider and verifies actual Godot HTTP
requests, clock progress while waiting, action execution, pause and reset. It
does not download/load a model or prove real-model quality. Python tests check
nested secret exclusion, memory isolation, malformed output, model preflight,
bounded scheduling, metrics/recovery and HTTP contracts. Existing Phase 1/2/2.5/2.6
suites remain regression checks.

Validation in this workspace: **17 Python tests** on installed Python 3.14;
Godot 4.7.2 **1436 + 253 + 1093 + 427 + 23 + 9 checks**, zero failures.
Actual NVIDIA-rendered viewport captures were inspected, including the
1024×720 layout and AI status. Ollama preflight returned DISCONNECTED, so actual
model inference and Python 3.11/3.12 execution have not been verified here.

If Python is missing, install 3.12 and reopen the terminal; inspect `py -0p`.
If DISCONNECTED, start Ollama and the Python terminal, check both URLs and Windows
port availability. If MODEL_UNAVAILABLE, match `.env` against `ollama list` and
manually choose/install the model. If DEGRADED, inspect `/metrics`, use 1x, reduce
LLM count, or increase decision interval. Cold model loads may exceed 30 seconds:
manually run `ollama run <your-tag>` once, or increase INFERENCE_TIMEOUT and Godot
request_timeout_seconds together (allow queue time too). Invalid JSON results are
rejected; use a model supporting structured instruction following.

Ollama requests follow the official [chat API](https://docs.ollama.com/api/chat)
and [model-list API](https://docs.ollama.com/api/tags), including a JSON schema,
nonstreaming response and a short keep-alive.
