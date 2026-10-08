# ESSAIM — La Dernière Chance

Academic multi-agent simulation for **Mondes Vivants — 5A IA & Big Data**.
The existing Godot project now implements **Phase 2.5: living world, incidents,
personalities and rumors**, extending Phases 1 and 2 entirely in GDScript.

## Run

Open the existing `project.godot` in Godot 4 and press **F5**. No manual nodes,
signal connections, plugins, services or API keys are required.
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
  300–600 simulated seconds; a configurable 2% of launches are false alarms.
- **Pause / Resume**, **1x / 2x / 5x / 10x** control the shared fixed clock.
- **Reset same scenario** restores the current seed, profiles, truth and incidents.
- **New random simulation** generates and displays a new seed. **Use seed**
  initializes exactly the value in the seed field.
- **Observer mode** hides actual capacities, occupancy, maintenance, alarm truth
  and impact timing. **Director mode** reveals them without changing outcomes.
  Its **False alarm** button forces a fake warning for demonstrations.
- Click an agent and scroll the sidebar for its 0–100 traits, panic, goal,
  shelter beliefs, rumors, memories and decisions. Click a shelter/card to inspect it.
- **Journal / Environment** tabs show timestamped decisions and incident reports.
- **WASD/arrows**, mouse wheel and **Fit map** control the map camera.
- Director **Export trace** saves a JSON trace; its full path appears in the journal.

All five academic shelter configurations remain editable. S5 exists in 50% of
seeded scenarios; **S5 ?** is a rumored site in Observer mode even when absent.
Agents start with approximate capacities and discover conditions locally or
through bounded communication. S3 relays deposited observations. Fifteen
archetypes influence decisions through individual traits and stress.

Autonomous maintenance, door, road, crowd and rat incidents have seeded schedules
and real temporary consequences. A real impact stops evacuation and shows
**SHELTERED / EXPOSED**, without assigning final deaths. A false alarm announces
**ALL CLEAR** and produces no impact. **Phase 3 has not started.**

## Configuration and documentation

Edit [resources/phase1.json](resources/phase1.json) for the existing city, shelters,
population, speeds and evacuation scoring. Edit
[resources/living_world.json](resources/living_world.json) for incident probabilities,
false alarms, perception/communication, approximate knowledge and stress parameters.
Stop and press F5 after editing; Reset uses already loaded settings.

Read [the Phase 2.5 beginner guide](docs/PHASE_25_GUIDE.md) for assumptions,
architecture, file changes, reproducibility, trace export and manual demonstrations.
Earlier phase guides are preserved as historical documentation.

## Validation

```powershell
& $GodotExe --headless --path . --editor --quit
& $GodotExe --headless --path . --script res://tests/test_phase1.gd
& $GodotExe --headless --path . --script res://tests/test_phase2.gd
& $GodotExe --headless --path . --script res://tests/test_phase25.gd
# Actual viewport screenshots, saved to ignored outputs/:
& $GodotExe --path . --script res://tests/render_phase25.gd
```

Executed on Godot 4.7.2: **1435 + 253 + 1093 checks, zero failures**.
Across 512 seeded scenarios, S5 existed 264 times (**51.6%**) and nine false
alarms were sampled. Tests include hidden-state isolation, local rumor disagreement,
S3 relay, autonomous incident effects and clearance, deterministic replay, safe
false alarms, original scene/camera/clock regressions and JSON export.
Godot import can exit zero after logging an error; inspect console output too.

The default 20-person population cannot overcrowd the academic shelter capacities.
Temporary capacity-one demos and automated boundary tests exercise rejection.
Road routes use the existing grid; there is no detailed traffic/collision model.
Ten-day survival and rationing, LLMs, Kafka and Storyteller controls remain future
work. Earlier `Main.py`, Python models/simulation/configuration and Python tests
are preserved but do not control the Godot game.
