# Citywide warning sirens

## Architecture and placement

scenes/three_d/WarningSiren.tscn is the reusable procedural prefab. Its script exposes pole/rooftop mount, sound radius, volume, pitch, mechanical rotation and initial ACTIVE/INACTIVE/DAMAGED/DESTROYED state. Runtime construction creates the four low-poly horns, pole/base, rotating emissive beacon, AudioStreamPlayer3D, selection area and optional coverage ring. No dynamic warning lights, rigid-body debris or navigation blockers are added.

SimulationManager owns warning configuration and siren truth. WarningSystem places three rooftop units at Police Station, Fire Station and School, plus intersection/dedicated towers spaced every 900 simulation units across the map. The default 2.5? map contains 18 sirens (2?: 15; 3?: 27). The rooftop units sit at their existing building centers. Ground towers are offset 20 simulation units from their intersections. Map size/reset regenerates this placement. Destroyed rooftop sirens become ground-level identifiable wreckage; damaged rooftop units follow the height of their collapsing building.

WarningNetwork3D is attached to the persistent isolated 3D world, independently of the city geometry subtree. Reset stops sources before freeing/rebuilding siren nodes. Streams are shared through WarningAudio's cache. The SubViewport enables 3D audio and has an explicit AudioListener3D. No change was made to navigation, shelters, the nuke countdown RNG or Ollama service/provider implementation.

## Sound and clock

CIVIL_DEFENSE_WAIL is the initial outdoor mechanical-style sweep. Optional EMERGENCY_BROADCAST windows begin after 12 simulated seconds and repeat every 75 simulated seconds; a broadcast starts at its own window's beginning, not halfway through a file. FINAL_WARNING takes precedence in the final 60 simulated seconds. Individual towers have deterministic startup offsets of up to 3 seconds. The existing 300?600 second seeded countdown remains unchanged.

During a real evacuation, playback phase, rotation and scheduling derive from elapsed simulation time. Playback pitch scales with simulation speed and the configured tower pitch; drift beyond 0.5 audio seconds is corrected by seeking. At 5?/10?, audio and voice are intentionally accelerated, not pitch-preserving time-stretched. Spatial sources stop while paused (also cancelling Godot's deferred 3D play requests), then resume at the frozen clock-derived phase. The quiet Director bed is stream-paused. Volume, mode changes and pause/resume do not resample the countdown.

At a real impact, the same fictional blast model determines tower damage: load at least siren_resistance (default 0.65) destroys a unit, lower positive load damages/disables it, and zero load leaves it intact/inactive. Damaged/destroyed units cannot be reactivated or tested. Surviving previously enabled units can play a bounded 4-second tail; explosion and tail use presentation time after the simulation stops, like the existing cinematic blast. Reset cancels both. All-clear stops the network without damage or explosion. Deactivate all also interrupts any tail. Siren states/configuration and destroyed/damaged/surviving counts are included in experiment archives and Director trace exports.

## Spatial mix

Each speaker uses AudioStreamPlayer3D inverse-square attenuation, stereo panning and its configured radius. At most four spatial tower sources are selected by default (configurable 1?8), prioritizing an individual test and otherwise the nearest sources. One very quiet nonspatial Director bed is available during an actual alert, and one explosion source is available at impact. These bounded extras are not additional tower voices. Combined warning buses use limiters; optional raycast occlusion routes blocked speakers through a low-pass bus. Indoor listener mode reduces level and applies muffling. Following an admitted agent also applies indoor listener attenuation.

Camera-relative Director mix projects the listener onto the camera's ground focus, retaining yaw for stereo, so zooming far above the city does not make all warnings disappear. Disable it for strict camera-position listening. Master volume and Director listener/muffling settings affect presentation only, not what agents know.

## Agent observations

A ground-plane radius/attenuation calculation runs every 0.5 simulated seconds. It includes per-tower volume and an indoor reduction for sheltered/indoors agents; it does not use Director amplification or the camera's position. Agents outside effective coverage remain unaware unless they later hear a siren or receive a local peer report. Initial hearing generates SIREN_HEARD; comprehensible speech generates a distinct WARNING_MESSAGE_RECEIVED. Observations are deduplicated and bounded, enter private memory, and produce private event-log entries. Public warning messages can propagate through the existing bounded rumor system with personality/trust-dependent credibility. Direct hearing influences panic/self-preservation and reaction delay; understandable official instructions adjust subjective alarm confidence. Existing personality policies and independent shelter decisions remain.

Only generic perceived warning text enters Llama's allowlisted memories/messages. Exact impact location, true countdown duration, tower damage truth and Director tests do not enter prompts. The observation calculation is a lightweight distance/indoor approximation, not a full acoustic propagation solver. Presentation uses additional geometric muffling; model hearing does not raycast every agent/tower pair. There are no newly simulated building interiors.

## Director controls

Open the **siren tower icon on the right rail**. The dedicated panel provides Activate all / Deactivate all, mode selector, master dB slider, announcements toggle, coverage rings, camera-relative mix, environmental muffling, indoor listener mode, individual selection/testing and state inspection. Click a physical tower to open its inspection. Scroll the panel for the complete readout.

Individual tests run for six real seconds and affect presentation only: no siren truth, agent observations, simulation phase or nuclear countdown changes. Manual network activation also never launches the countdown. In Preparation its sound uses presentation time; once the city clock starts, normal clock synchronization applies. Activate all is disabled after impact; intact surviving units can still be tested individually. Ordinary Launch nuclear alert remains the only nuke-alert entry point.

Configuration: resources/warnings.json. Per-unit records expose radius_world, volume_db, pitch, mount, mechanical_rotation and startup offsets. Optional siren_overrides in the JSON maps IDs (for example WS01) to radius_world, volume_db, pitch, mechanical_rotation and initial state overrides. Tower volume affects acoustic perception against a fixed -16 dB reference; muting the Director master does not change agents. Audio import/generation, exact filenames and provenance are documented in assets/audio/warnings/README.md. No external recording was imported; all included files are explicitly temporary local procedural/synthesized assets.

## Tests

```powershell
$GodotExe = 'C:/Users/Moham/Downloads/godot/Godot_v4.7.2-stable_win64_console.exe'
& $GodotExe --headless --path . --editor --quit
& $GodotExe --headless --path . --script res://tests/test_warnings.gd
& $GodotExe --path . --script res://tests/test_warning_audio.gd
& $GodotExe --headless --path . --script res://tests/test_phase35.gd
& $GodotExe --headless --path . --script res://tests/test_phase3.gd
.venv/Scripts/python.exe -m tests.run_phase3_http --godot $GodotExe
```

The audio test uses the real WASAPI mixer on this machine, captures warning-bus PCM with Master muted, compares left/right and near/far channel energy, and checks settled pause silence. It saves actual scene/UI images in outputs/warning-panel.png, outputs/warning-tower.png and outputs/warning-destroyed-tower.png. It restores output mute state on normal completion. The headless suite checks state, timing, privacy, observation reach, indoor comprehension, reset, damaged/surviving sources and all-clear. The phase 3.5 suite checks preserved city/navigation/destruction/reset and archival behavior. See the final result table below for executed results; no subjective listening assessment or sustained FPS benchmark is claimed.

### Executed results

| Suite | Result |
|---|---|
| Warning state/clock/perception suite | 68 checks, zero failures |
| Real WASAPI spatial audio capture | 4 checks, zero failures |
| Existing 3D/navigation/camera regression | 2,897 checks, zero failures |
| Phase 3.5 city/destruction regression | 861 checks, zero failures |
| LLM observation/action regression | 17 checks, zero failures |
| Scripted HTTP transport | 11 checks, zero failures |
| 150-agent scripted transport | 49,591 checks, zero failures |
| Existing UI suite | 33 checks, zero failures |
| Python unittest discovery | 18 tests passed |
| Actual llama3.2:1b inference | MOVE_TO_SHELTER / S1 applied as MOVING |

The PCM capture measured right-side energy greater than left for an emitter on the right, reversed that balance when the listener moved, and measured distant energy over four times lower than nearby energy. Settled paused channel energy was (0,0). WAV audits found zero clipped samples; peak amplitudes were 0.2127 (wail/final), 0.2501 (speech) and 0.3500 (explosion). A deferred-play pause race found during testing was fixed by cancelling spatial sources on pause and reconstructing their clock phase on resume. Capture tests wait for the real driver buffer to settle. Temporary test AI service was started solely for live inference verification and stopped afterward; existing Ollama was left running.

### Changed files for this warning extension

Added: resources/warnings.json; resources/icons/sirens.svg and import metadata; scenes/three_d/WarningSiren.tscn; scripts/warning_system.gd; scripts/warning_audio.gd; scripts/siren_controls.gd; scripts/three_d/warning_siren.gd; scripts/three_d/warning_network_3d.gd; tests/test_warnings.gd; tests/test_warning_audio.gd; tools/generate_warning_audio.py; tools/generate_warning_voice.ps1; assets/audio/warnings/README.md and four temporary WAV assets with Godot import metadata; this guide. Godot also generated script .uid files.

Extended: scripts/simulation_manager.gd (network truth, warning perception and destruction/archive metrics); scripts/map_view_3d.gd (3D listener/network, reset and tower selection); scripts/main.gd (Siren drawer, inspection and trace export); scripts/evacuation_effects.gd (compatibility facade replacing the old global tone); scripts/rumor_system.gd (trusted local peer warnings); README.md (current controls/documentation). Existing map-overhaul work was preserved, with a pre-warning working-tree ZIP at outputs/checkpoints/warning-before.zip.
