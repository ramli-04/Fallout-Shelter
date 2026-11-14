# Phase 5 — social evacuation runtime

The default runtime now creates **100 agents: 65 civilians and 35 authorities**.
Open **CONFIGURE SIMULATION** before starting. The top bar's **CONFIGURE / SOCIAL
DIRECTOR** button also opens configuration, population histograms, metrics and replay.
The existing sirens, Director impact controls, five shelters, admission, incidents,
agent inspector and nuclear damage model remain in use.

## Start

Godot runs on Windows. Its pre-run population and road preparation use the local
Python environment; install dependencies there even when inference runs in Docker:

```powershell
.\.venv\Scripts\python.exe -m pip install -r ai_service/requirements.txt
docker compose -f compose.yaml -f compose.kafka.yaml -f compose.gpu.yaml up -d --build
```

Run `project.godot` with Godot 4.7.2, configure the scenario, then **START SIMULATION**.
Use the existing warning button to begin evacuation. Models are not automatically
downloaded. A missing model, disabled cloud provider, invalid decision or timeout
uses the existing rule fallback.

Default AI: **30 adult LLM agents and 70 rule agents**, with 100 independently
active simulation records. A/B/C default to local `qwen2.5:0.5b`, `llama3.2:1b`,
and `qwen2.5:1.5b`. Adult assignments skip children and groups assigned to rules;
the generator rejects a requested LLM count exceeding eligible adults.
Global HTTP capacity defaults to 8, each provider admits 2 requests, and Ollama
retains its own GPU scheduling limits. These are different from agent population.
Cloud adapters remain available through the menu, but require explicit backend
cloud opt-in and existing credentials. Credentials are never stored in presets.

## Configuration and population — 5.1

`resources/social_config.json` is the version-1 default. Save/load uses
`user://social_preset.json`; the menu displays its absolute path after saving.
Population edits reconcile total/civilian/authority counts. Invalid counts,
guardian availability, fractions, models, versions and inference limits are rejected.
The legacy Phase 4 experiment selector still switches back to its 30/120-agent
runtime; the new configuration menu switches back to the social runtime.

`ai_service/social_population.py` uses independent NumPy `Generator` streams for
IQ, occupations, traits, households and devices. `SeedSequence`/PCG64 isolate IQ
from authority assignment. The cached default manifest records NumPy version,
configuration and its hash; custom seeds/settings regenerate before the clock runs.
IDs persist across resets of the same scenario and are scoped by run ID in events.

IQ is sampled from Normal(mean, standard deviation squared), without forced bins
or role stratification. Actual sampled mean, population SD and histogram are shown.
It is a synthetic covariate, not a complete scientific model of cognition. Its only
rule-policy effect is a bounded change in subjective travel-time estimation:
default at most 5%, configurable up to 10%. It never assigns role, empathy, morality
or survival. The IQ histogram includes both distribution tails.

Authority profiles preserve 12 police, 8 fire, 7 medical, 5 civil protection and 3
commanders. Civilian **role profiles** preserve 25 residents, 15 family members,
10 students/young adults, 8 elderly and 7 technicians. `role_profile`, occupation,
age, school and household membership are separate attributes, so schoolchildren
and parents are not counted as extra agents.

## Households and school — 5.2

Families link generated agent IDs, including parents, children, spouses, siblings
and grandparents. Some children have two guardians. Staff are drawn from the
existing population. Students begin at the existing School POI's assembly area.
The additional school marker and pickup building identify that area in 3D.

Parents initially remember uncertain schedules, not live child coordinates.
Local observation, phone calls, school replies and family group messages update
their private last-known locations. A parent may seek that location, accept school
instructions, or continue to a shelter depending on trust and family priority.
Children follow a nearby guardian or assigned school supervisor; they do not use
the adult LLM evacuation policy. Staff select an evacuation destination through
their own existing shelter beliefs and notify reachable guardians. Separation,
missed announcements, stale locations and differing decisions are possible outcomes.

## Communications — 5.3

Phones have an owner, connection, battery field, contacts, family groups, bounded
message history and call history. Battery depletion is not enabled. Connection
availability, congestion, delivery delay and recipient health/device availability
affect delivery. Calls, texts, family chats and social DMs target their recipients.

ESSAIM CIVIL DEFENSE ALERT messages contain issuer, ID, timestamp, severity,
coverage, instructions and expiry. Nuclear, evacuation, shelter-in-place, closure,
school and final warnings are supported. A phone sound and visible Director alert
card accompany delivered alerts. Existing spatial sirens remain separate.

Social posts retain author, original source, time, audience, claims, credibility,
readers, comments, reactions and propagation history. Sharing can mutate a boolean
claim. Reading a claim updates an agent's belief, not world truth. Credible private
claims about shelter occupancy can affect that agent's shelter choices. Direct
evidence overrides rumors and can change source trust. Known observations changing
over time are not counted as rumor corrections.

## Authorities and closures — 5.4

Commanders issue addressed orders; responders report through phones. Orders can
fail delivery or be distrusted. Police create/remove barriers. Medical, fire and
civil-protection agents assist nearby injured people; accident witnesses can send
reports that responders travel toward. School staff escort their students.

Closures disconnect graph edges and update the pedestrian obstacle grid. Civilians
learn them locally or by communication, rather than receiving a global closure
map. Car motion checks actual barriers. Authorized emergency routes may pass
police checkpoints; accident closures apply to emergency vehicles too. Elevated
closures are separated from ground-level pedestrian obstructions.

## Roads and transport — 5.5

The previous renderer emitted separate quads with different segment normals at
shared vertices, overlapped complete ribbons at junctions, and drew an unconnected
roundabout. The replacement buffers the actual graph paths, unions each surface
layer, and uses GEOS constrained triangulation including holes. Coplanar road pieces
therefore share one coverage surface. Asphalt, sidewalks and markings have explicit
vertical separation. Terrain sampling subdivides long triangles. The unconnected
roundabout was removed as part of the road reconstruction.

Curved streets, diagonal junctions, mountain approaches, highway and two ramps
remain. Highway/ramp geometry is now connected to the same graph, with elevation
tracking for vehicles. Graph costs use spline length, not just endpoint distance.
**F8**, or the Director checkbox, shows network lines and vehicle identifiers.

Cars, police cars, ambulances, fire trucks and civil-protection vehicles use kinematic road following,
acceleration/braking, passenger limits, boarding/disembarking, car following and
junction yielding. Drivers walk to their parked cars. Congestion can stop traffic;
accidents injure occupants, create closures, generate witness evidence and are
cleared after a configurable simulation event lifetime. Nuclear damage also reaches
vehicles and the school.

This is a simplified traffic model, not a rigid-body driving simulator. The optional school bus is not implemented. Vehicle lane offsets are visual; collision avoidance and
intersection priority use the shared road centerline model. Complex traffic can
gridlock. Geometry tests establish planar coverage/integrity, not a proof that
every camera position and terrain seed has zero visual artifacts.

## Execution, isolation and events — 5.6

Godot's `AgentObservationBuilder` constructs private observations. Python applies
another explicit nested allowlist. Prompts contain the agent's profile, memories,
acquired shelter/social beliefs, own inbox, remembered family locations and nearby
visible agents. No global family tracker, accident list, hidden supplies, impact
coordinates or other minds enter that boundary. Unknown subjects are absent;
acquired evidence distinguishes KNOWN, BELIEVED and RUMORED.

Async mode keeps motion, communication and perception running while requests are
pending. Rule decisions are staggered by agent. Provider actors, deadlines, stale
result rejection and fallback remain in the existing Python runtime. There is no
new central FIFO inference queue. Experimental sync mode is a **simulation-clock
barrier over in-flight requests**: HTTP remains nonblocking, but the clock waits.
It is not a second GPU execution engine.

Versioned social event types cover observations/beliefs/decisions, families,
communications, orders/alerts, roadblocks, traffic, vehicles and school evacuation.
They reuse `essaim.world.events`; existing AI topic names are preserved. Envelopes
include run/event IDs, version, source, simulation time and UTC wall time. A single
client batch is in flight to preserve causal send order. The backend validates and
durably deduplicates IDs in SQLite before Kafka publishing, with a persistent
pending-publication ledger. Kafka is at-least-once; consumers must honor event IDs.
Unsent client events are also present in the local audit. Closing/resetting an
offline client does not automatically reimport that audit into Kafka.

## Director, experiments and replay — 5.7

The Director tab is explicitly omniscient. It shows population/IQ/stress,
households, school, calls/messages/posts, rumors, alerts/orders, vehicles, closures,
congestion, emergency vehicle positions and existing AI metrics. The agent inspector
shows that selected mind's beliefs, provenance, inbox and last-known family locations.

Presets A–K and L sync/async configure phones, social media, rumors, trust,
roadblocks, congestion, family priority and mixed inference. Initial records include
seed and full configuration. `outputs/phase5/<run>.jsonl` contains typed events and
one-second state frames. Serialization/file writing runs on a worker thread.
Final `*-metrics.json` records survival, shelter arrival, family reunion, accidents,
congestion, rumor corrections, compliance events, alert reach, consensus among
acquired claims and AI token/latency/fallback metrics. Counts are synthetic
experimental metrics; accident probabilities are not calibrated real-world rates.

Load a recorded run in the Director tab and scrub the slider. Replay recreates
matching geography/population, restores recorded frames and makes no new LLM calls.
It is one-second snapshot replay from the audit, not a deterministic resimulation
of every physical tick from semantic events alone. Live async runs can differ with
provider timing; replay preserves the recorded outcome.

## Validation

Run:

```powershell
.\.venv\Scripts\python.exe -m unittest discover -s tests -p 'test_*.py'
& $GodotExe --headless --path . --script res://tests/test_phase5.gd
& $GodotExe --headless --path . --script res://tests/test_phase5_ui.gd
& $GodotExe --headless --path . --script res://tests/test_phase5_transport.gd
& $GodotExe --headless --path . --script res://tests/test_road_surface.gd
.\.venv\Scripts\python.exe -m unittest tests.test_road_geometry
& $GodotExe --path . --script res://tests/render_phase5.gd
```

Current test evidence and performance measurements are in
`outputs/phase5-*-verified.log`, `outputs/phase5-*-regression.log`,
`outputs/phase5-live-http.json` and `outputs/phase5-performance.json`.
The Python suite includes existing async/provider/ledger tests as well as new
population, schema, isolation and planar geometry tests. Godot covers population,
school presence, private knowledge, communication, alerts, closures, passenger
capacity, bounded motion, actual driving, school evacuation, sync/async clock
behavior, replay, impact compatibility, reset, preset round trips and menu behavior.

The existing Phase 4, warning and valley tests have passed with `-- --legacy-runtime`.
The valley junction-count assertion was updated from 65 to 166 for the connected
highway. This does **not** mean every historical test suite is green: Phase 1's
old 150-agent/speed assertions failed (34 failures); the old Phase 2 run hit its
120-second timeout. Those historical baselines have not been rewritten or certified.

A real HTTP run connected all three local models and Kafka, generated 100 agents,
and accepted then deduplicated the same event. SQLite confirmed Kafka publication.
Across three real smoke runs, seven of nine inference attempts returned valid decisions; two used fallback. The final shared-GPU run returned three valid decisions.
Tiny-model output reliability is a remaining limitation, not a passed-inference claim.
Cloud providers and long-duration multi-seed statistical outcome studies have not
been validated. The optional school bus remains unimplemented.

The short render benchmark uses rule policies for the 100 game agents. The final
shared-GPU smoke run also sent three simultaneous real model requests while rendering;
its results are in `outputs/phase5-shared-gpu-final.json`. No other headless test was
running during that final measurement. It measured **14.8 ms median / 32.7 ms p95**
frames and 53 vehicles. The latest rule-only run measured **14.8 ms median / 31.1 ms
p95** after adding broad-phase obstacle filtering and staggering reconsideration
at the configured decision interval. This is a short smoke measurement, not a
frame-rate guarantee or a long-duration 100-LLM benchmark. Render memory was about
47 MB; startup about five seconds; road geometry about 86,000 vertices. Earlier,
unoptimized measurements are retained separately and are not the final timings.

Verified suites on this checkout:

| Suite | Result |
|---|---:|
| Python discovery (including async mocks, schemas and geometry) | 51 tests passed |
| Social Godot | 956 checks, 0 failures |
| Configuration UI | 6 checks, 0 failures |
| Transport behavior | 8,487 checks, 0 failures |
| Road graph/continuity | 281 checks, 0 failures |
| Existing Phase 4 | 12 checks, 0 failures |
| Existing warnings | 93 checks, 0 failures |
| Existing valley world | 1,654 checks, 0 failures |

The Python test process still emits its existing Starlette deprecation/resource
warnings. Historical Phase 1/2 caveats above remain; they are not included in this
passed-suite table.


## Changed implementation files by phase

| Phase | Principal files |
|---|---|
| 5.1 | `social_population.py`, `social_config.gd`, `resources/social_*.json`, population tests |
| 5.2–5.4 | `social_simulation.gd`, `social_alert_widget.gd`, `agent_beliefs.gd`, social/transport tests |
| 5.5 | `road_geometry.py`, `road_graph.gd`, `city_map.gd`, `valley_environment.gd`, `social_world.gd`, geometry tests |
| 5.6 | `agent_observation.gd`, `contracts.py`, `schemas.py`, `llm_actions.gd`, `llm_bridge.gd`, `social_events.py`, `main.py`, `events.py`, `runtime.py` |
| 5.7 | `social_dashboard.gd`, `population_histogram.gd`, `social_recorder.gd`, main UI/inspector, render/UI tests |

Integration also updates `simulation_manager.gd`, agent rendering/reactions,
the bounded analytical IQ term, requirements and the default local model group C.
