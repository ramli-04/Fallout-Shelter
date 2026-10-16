# ESSAIM — shared multi-LLM experiments

# Phase 4 concurrent agents

The map now includes seeded large buildings, Central Park and a hilly green
reserve. See [procedural map controls and terrain notes](docs/PROCEDURAL_MAP.md).

The current runtime uses 30 seeded agents split 10/10/10 across configurable
provider groups, asyncio actors, and an optional Kafka bridge. See
[Phase 4 setup, measurements, and limitations](docs/PHASE_4.md) for the current
startup commands. Earlier phase guides describe historical implementations.

Current scheduling: **three concurrent requests, one per shared model**.
Inspect prompts, raw answers and live model metrics at
http://127.0.0.1:8765/inspector (or Godot Settings → Open LLM prompt inspector).
See [concurrency and trace guide](docs/LLM_INSPECTOR.md).

Default: **30 agents** sharing qwen2.5:0.5b, llama3.2:1b and qwen2.5:1.5b
(18/9/3). The 120-agent preset (72/36/12) requires benchmark opt-in.
See [installation, scheduler, Director metrics and experiment settings](docs/MULTI_LLM.md).

# Docker startup

Start Docker Desktop with Linux containers, then run from the project folder:

```powershell
docker compose up -d ollama
docker compose run --rm model-pull  # explicit first-time model download
docker compose run --rm model-pull pull qwen2.5:0.5b
docker compose run --rm model-pull pull qwen2.5:1.5b
docker compose up -d --build ai-service
Invoke-RestMethod http://127.0.0.1:8765/health
```

Open Godot and press F5. The old AI startup scripts are replaced by Compose.
See [Docker setup, GPU option and troubleshooting](docs/DOCKER.md).

# Citywide warning sirens

The right-rail **siren tower icon** opens network activation, individual tests, audio modes/volume, coverage and damage inspection. Physical rooftop/tower speakers use spatial audio, scheduled local announcements and final-minute urgency, synchronized with the existing simulation clock. Agents receive only perceived warnings. [Warning system guide and test results](docs/WARNING_SIRENS.md) ? [Temporary audio provenance and recording import](assets/audio/warnings/README.md).

# Current phase: 3.5 ? expanded city and nuclear damage

The existing project now has a configurable 2?3? city, five service POIs, reusable animated vault entrances, Director impact selection/preview, actual building and shelter destruction, blast survival metrics and same-seed reset. Start in Preparation, open the Settings gear, and scroll to **NUCLEAR IMPACT CONTROLLER**. Read [the Phase 3.5 guide](docs/PHASE_35_GUIDE.md) for controls, configuration, tests and limits, and [the architecture checkpoint](docs/PHASE_35_ARCHITECTURE.md).

Phase 3.5 supersedes the historical statements below that impact is cosmetic or survival is not modeled. Immediate blast survival is now modeled; ten-day survival remains future work. Current AI configuration uses the shared 30/120-agent model pool described above.

---

# ESSAIM â€” La Dernière Chance

Academic multi-agent simulation for **Mondes Vivants â€” 5A IA & Big Data**.
The existing Godot project now adds **Phase 3: local Ollama decisions** to the
Phase 2.6 3D city and Director camera. Godot remains authoritative for world
truth and physical actions; a Python HTTP service handles inference and private memory.

## Run

Open the existing `project.godot` in Godot 4 and press **F5**. No manual nodes,
signal connections, plugins or API keys are required for rule fallback.
For real LLM decisions, follow [the Phase 3 setup guide](docs/PHASE_3_GUIDE.md).
Defaults are five local LLM agents and fifteen rule agents; unavailable inference
uses the existing rule policy. No model is downloaded automatically.
Tested with the installed **Godot 4.7.2 stable**.

```powershell
Set-Location 'C:\Users\Moham\OneDrive\Desktop\ESSAIM'
$GodotExe = 'C:\Users\Moham\Downloads\godot\Godot_v4.7.2-stable_win64_console.exe'
& $GodotExe --path . --editor
# Or run directly:
& $GodotExe --path .
```

## Controls

- **Start simulation** runs the city and local conversations without a siren.
- **Launch nuke** activates the siren and evacuation. Its hidden warning lasts
  300â€“600 simulated seconds; a configurable 2% of launches are false alarms.
- **Pause / Resume**, **1x / 2x / 5x / 10x** control the shared fixed clock.
- **Reset same scenario** restores the current seed, profiles, truth and incidents.
- **New random simulation** generates and displays a new seed. **Use seed**
  initializes exactly the value in the seed field.
- **Director is the only viewing mode.** Its **False alarm** button forces a
  fake warning for demonstrations. Inspection never gives agents Director knowledge.
- Click an agent and scroll the sidebar for its 0â€“100 traits, panic, goal,
  shelter beliefs, rumors, memories and decisions. Click a shelter/card to inspect it.
- **Journal / Environment** tabs show timestamped decisions and incident reports.
- With the pointer over the city: **WASD/arrows** pan, **wheel** zooms,
  **middle drag** pans, **right drag** orbits/tilts, **double-click/F** focuses
  an agent and **Home** restores the diagonal overview. UI input stays separate.
- Admitted agents disappear outdoors; the inspector's **agent picker** still
  lets you inspect their records inside shelters.
- Director **Export trace** saves a JSON trace; its full path appears in the journal.

All five academic shelter configurations remain editable. S5 exists in 50% of
seeded scenarios; absent S5 has no 3D structure or entrance (try seed **2**).
Agents start with approximate capacities and discover conditions locally or
through bounded communication. S3 relays deposited observations. Fifteen
archetypes influence decisions through individual traits and stress.

Autonomous maintenance, door, road, crowd and rat incidents have seeded schedules
and real temporary consequences. A real impact stops evacuation and shows
**SHELTERED / EXPOSED**, without assigning final deaths. A false alarm announces
**ALL CLEAR** and produces no impact. **Local LLM integration is implemented; model installation is manual.**

## Configuration and documentation

Edit [resources/phase1.json](resources/phase1.json) for the existing city, shelters,
population, speeds and evacuation scoring. Edit
[resources/living_world.json](resources/living_world.json) for incident probabilities,
false alarms, perception/communication, approximate knowledge and stress parameters.
Edit [resources/visual_3d.json](resources/visual_3d.json) for camera speed,
zoom/tilt limits, smoothing, shadows and navigation debug visualization.
Stop and press F5 after editing; Reset uses already loaded settings.

Read [the Phase 2.6 beginner guide](docs/PHASE_26_GUIDE.md) for controls,
architecture, the complete file list, navigation choices and manual tests.
The [Phase 2.5 guide](docs/PHASE_25_GUIDE.md) retains cognitive/event assumptions.
Earlier phase guides are preserved as historical documentation.

## Validation

```powershell
& $GodotExe --headless --path . --editor --quit
& $GodotExe --headless --path . --script res://tests/test_phase1.gd
& $GodotExe --headless --path . --script res://tests/test_phase2.gd
& $GodotExe --headless --path . --script res://tests/test_phase25.gd
& $GodotExe --headless --path . --script res://tests/test_phase26.gd
# Actual viewport screenshots, saved to ignored outputs/:
& $GodotExe --path . --script res://tests/render_phase26.gd
```

Executed on Godot 4.7.2: **1436 + 253 + 1093 + 427 checks, zero failures**.
Across 512 seeded scenarios, S5 existed 264 times (**51.6%**) and nine false
alarms were sampled. Tests include hidden-state isolation, local rumor disagreement,
S3 relay, autonomous incident effects and clearance, deterministic replay, safe
false alarms, original scene/camera/clock regressions and JSON export.
The 3D suite verifies connected Godot navigation paths, building clearance,
raycast selection, camera/UI isolation, absent-S5 visuals, indoor inspection and
identical full evacuation results against an independent simulation controller.
Godot import can exit zero after logging an error; inspect console output too.

The default 20-person population cannot overcrowd the academic shelter capacities.
Temporary capacity-one demos and automated boundary tests exercise rejection.
Movement retains the deterministic road planner and maps its positions onto XZ.
The connected NavigationMesh and each NavigationAgent3D maintain valid 3D paths
without replacing the model's clock or route. There is no crowd pushing/RVO,
detailed traffic model or walkable shelter interior.
Ten-day survival and rationing, Kafka and Storyteller controls remain future
work. LLM setup, provider contracts, status, metrics and limitations are documented
in [PHASE_3_GUIDE.md](docs/PHASE_3_GUIDE.md). Earlier `Main.py`, Python models/simulation/configuration and Python tests
are preserved but do not control the Godot game.
# Historical setup: 150 AI agents

The interface uses a full-window map with a warm-white, sage and charcoal palette. Press the play triangle to begin; the two bars pause. People, house and journal icons on the right toggle Agents, Shelters and Logs; selecting an entity opens its information automatically. All action buttons have descriptive hover tooltips. Bottom controls sit on a 50%-transparent toolbar with opaque icons. The gear opens Settings, containing seed input, apply-seed and random-scenario controls. The fullscreen icon or F11 toggles display mode. Escape closes the active panel.

The scenario now has 150 agents, all configured for local llama3.2:1b, and shelter capacities reduced to one twentieth. See [population and scheduling notes](docs/POPULATION_AI.md) and [startup instructions](ai_service/README.md). Older Phase 3 reports describe the earlier one-agent milestone.
