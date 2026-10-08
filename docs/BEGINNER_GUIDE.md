# ESSAIM: your first Godot project

> This is the historical Phase 1 guide. The current project implements Phase 2;
> read [PHASE_2_GUIDE.md](PHASE_2_GUIDE.md) for the current Start behavior,
> countdown, movement, admissions, speed controls and impact.

This delivery implements **Phase 1: the visual prototype**. It runs entirely in
Godot with GDScript. No Python, plugins, downloaded artwork, accounts, or API keys
are needed. The agents are deliberately idle; the preparation clock counts up.
The countdown stays `--:--` because evacuation and impact are later phases.

## 1. What the files do

| File | Purpose |
| --- | --- |
| `project.godot` | Godot's project settings, window settings, and F5 main scene. |
| `scenes/main.tscn` | The root scene. Its script creates and connects the dashboard automatically. |
| `scenes/agent.tscn` | Reusable scene instantiated once per agent. |
| `scenes/shelter.tscn` | Reusable scene instantiated once per existing shelter. |
| `scripts/main.gd` | Builds the interface and connects buttons and manager signals. |
| `scripts/simulation_manager.gd` | Owns run data, random seeds, initialization, the preparation clock, and events. |
| `scripts/city_map.gd` | Draws roads, blocks, buildings, parks, and provides clear sidewalk spawn slots. |
| `scripts/map_view.gd` | Creates the map's separate viewport, camera, object selection, pan, and zoom. |
| `scripts/agent.gd` | Draws an idle agent and its selection ring. |
| `scripts/shelter.gd` | Draws shelter shapes, labels, and selection rings. |
| `scripts/dashboard.gd` | Shared UI colors, button styles, and shelter cards. |
| `resources/phase1.json` | Editable seed, profiles, speeds, shelter data, positions, and colors. |
| `tests/test_phase1.gd` | Godot integration tests without an external test plugin. |
| `tests/render_phase1.gd` | Optional screenshot tool for checking the real rendered interface. |
| `docs/PHASE1_NOTES.md` | Specifications, assumptions, scope, and validation notes. |

Earlier Python scaffold files remain in the repository from the previous task.
Godot does not load or execute them. `resources/phase1.json` is the configuration
for this prototype; the older `config/` directory does not control Godot.

## 2. Open the project

1. Open Godot 4's **Project Manager**.
2. Click **Import** (sometimes shown as **Import Existing Project**).
3. Choose `C:\Users\Moham\OneDrive\Desktop\ESSAIM\project.godot`.
4. Click **Import & Edit**. Let the initial import finish.
5. You do not need to create nodes, import assets, or connect signals yourself.

The project was tested with your installed **Godot 4.7.2**. Use this same version
for repeatable random initialization. There is no guarantee that RNG results will
be identical between different Godot versions.

## 3. Run it

Press **F5**, or click the triangular **Run Project** button near the editor's
top-right corner. If you are asked to choose a main scene, select
`scenes/main.tscn`; the project file already sets this automatically.

The editor's 2D view may appear empty before running: this prototype builds its
dashboard and draws its map when the main scene starts. That is expected.

You should see a dark dashboard, a city, 20 small agents, five shelter cards,
and an initialization journal. S5's card remains visible even when its seeded
existence draw says it is absent; an absent S5 has no map marker.

## 4. Move the camera

Click inside the map, or keep the pointer over it. Hold **WASD** or the **arrow
keys** to pan. Scroll the **mouse wheel** over the map to zoom in or out. Zoom is
centered around the pointer and has limits to avoid losing the map completely.
Click **Fit map** to restore the overview. Resizing the window also refits it.
Scrolling over the sidebar scrolls the sidebar instead of zooming the map.

## 5. Select an agent

Zoom in if needed and click one of the small circles. Blue circles are civilians;
gold circles with a cross are authorities. A white selection ring appears, and
the sidebar shows ID, role, speed, risk tolerance, trust, sociability, position,
and state. All agents stay idle even after Start.

## 6. Select a shelter

Click a larger colored shelter marker or one of the five sidebar cards. The
inspector shows capacity, resources, distance category, special risks, and
whether the shelter exists in this run. Scroll the sidebar if the details are
below the visible part of a smaller window.

`Unknown` supplies means no quantity is known. It does **not** mean zero.
`Abundant` is a qualitative label; its exact quantity has not been modeled yet.

## 7. Start, Pause, Reset

- **Start** begins or resumes the preparation clock at the bottom right.
- **Pause** freezes that clock. Camera and inspection still work.
- **Reset** stops and zeroes the clock, rebuilds the same run using the same seed,
  clears selection, restores the camera, and replaces the journal with the
  initial events. Agent properties, positions, and S5 existence repeat.
- **Speed 1x** means one simulated preparation second per real second. To change
  it for a later run, edit `simulation_speed` in the configuration and rerun F5.

Stop the game with **F8**, or close its window.

## 8. Find and understand errors

The editor's bottom **Output** and **Debugger** panels contain errors. Click a
red error to see its script and line. A message such as `Invalid JSON` identifies
a configuration problem; check commas, quotation marks, and brackets in
`resources/phase1.json`. A `res://` path means a file relative to this project.

For configuration errors, the prototype also displays a message in the inspector
and disables the controls. Fix the file, stop the game, and press F5 again.

## 9. Files to modify later

Start with `resources/phase1.json`. Change `seed` to explore another initial run.
Positions are `[x, y]` world coordinates, with `(0, 0)` at the upper-left of the
map. The map is 1,800 by 1,080 world units. Keep positions inside these bounds.
The default is 20 agents with 4 authorities. Counts up to 24 are supported if
there are enough spawn slots clear of shelter plazas.

Use `city_map.gd` for map geometry, `agent.gd` and `shelter.gd` for appearance,
and `dashboard.gd` for styles. Add future agent behavior in the simulation layer;
keep movement, decisions, and resource rules out of drawing functions.

Useful GDScript concepts: a **scene** is a reusable tree of nodes; `extends`
chooses the script's node type; a **Dictionary** stores named properties;
`_ready()` runs when a node enters the scene; `_process(delta)` receives elapsed
frame time; `_draw()` renders built-in shapes; a **signal** announces a change
to another part of the project. Here signals keep the UI separate from run data.

## 10. Report an error

Send Codex the exact Godot error text, the script path and line, your Godot
version, your seed, and the actions immediately before the problem. Include the
edited configuration if relevant. A screenshot is useful for layout problems.

## Manual acceptance check

1. Press F5. Confirm 20 agents, five cards, and shelter/agent journal messages.
2. Click an agent and S1; check the inspector and white selection ring.
3. Click S3; confirm resources say `Unknown`, not `0`.
4. Start, wait a few seconds, Pause, and confirm the clock freezes.
5. Pan with D/right arrow, zoom with the wheel, and click Fit map.
6. Reset. Confirm `00:00`, unchanged profiles and S5 presence, and no duplicate nodes/cards.
7. Resize to a smaller window. Scroll the sidebar to see the full inspector.
8. Stop. Change the seed in JSON, run again, and inspect S5's new draw.
9. Restore seed 42 when finished. Check that Output/Debugger contains no errors.

## Optional PowerShell commands

These use the Godot executable already installed on your computer:

```powershell
Set-Location 'C:\Users\Moham\OneDrive\Desktop\ESSAIM'
$GodotExe = 'C:\Users\Moham\Downloads\godot\Godot_v4.7.2-stable_win64_console.exe'

# Open the editor, or run the game directly:
& $GodotExe --path . --editor
& $GodotExe --path .

# Import/parse the project, then run integration tests:
& $GodotExe --headless --path . --editor --quit
& $GodotExe --headless --path . --script res://tests/test_phase1.gd

# Capture a rendered screenshot (requires a graphical display):
& $GodotExe --path . --resolution 1920x1080 --script res://tests/render_phase1.gd -- phase1-desktop.png
```

The test command returns a nonzero exit code if a check fails. Generated
screenshots are written to `outputs/`, which is excluded from Git.
