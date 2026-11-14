# ESSAIM Rendering Asset Audit

Audit date: 2026-11-12. Scope: `assets/`, `resources/`, `scenes/`, and `models/`, plus the Godot rendering settings and the scripts that create world visuals. The scan found 84 project files in those folders (three additional Python bytecode files are local build output).

## Inventory

| Asset group | Files and format | Resolution / approximate GPU use | Current use and replacement decision |
|---|---|---|---|
| UI icons | 17 SVG files: `agents`, `alert`, `apply`, `close`, `export`, `false_alarm`, `fullscreen`, `logs`, `overview`, `pause`, `play`, `random`, `reset`, `settings`, `shelters`, `sirens`, `windowed` | 16 icons use a 24×24 view box and `sirens.svg` uses 32×32. At RGBA8, intrinsic raster storage is about 40 KiB total, before driver alignment. SVG imports use scale 1, no mipmaps, and no VRAM compression. | Used by dashboard controls and mode panels through `Dashboard.icon_button`. Kept as vector UI assets; an atlas would not materially reduce this small set. |
| Warning audio | 4 WAV files and 1 MP3: `temporary_civil_defense_wail.wav` (1,058,444 B), `temporary_emergency_broadcast.wav` (504,896 B), `temporary_explosion.wav` (176,444 B), `temporary_final_warning.wav` (352,844 B), and `bomb_dropping_cc0.mp3` (121,968 B) | No GPU texture use. The four mono PCM WAV sources total 2,092,628 B and are about 2 MiB decoded at their source rates. MP3 decode memory depends on the imported stream. | Warning WAV files are local fallback audio selected by `warning_audio.gd`; the bomb MP3 is loaded by `bomb_drop.gd`. License/provenance notes remain beside the files. |
| 3D meshes and character/vehicle models | No authored `.glb`, `.gltf`, `.obj`, `.fbx`, or `.blend` models were found. The 15 `.tscn` files are compact Godot scenes, not imported model files. | No source-model texture resolution or per-file GPU estimate exists. Geometry is generated from GDScript at run time. | Buildings, roads, terrain, vegetation, shelters, agents, and the earlier vehicle proxies are generated from map data and reusable scripts. Existing geography and collision sources remain authoritative. |
| Materials and animation | No `.tres`, `.res`, or `.anim` resources were found. | Material and animation memory is runtime-owned and must be measured in the renderer. | `StandardMaterial3D`, `Mesh` resources, character clips, and vehicle parts are generated and cached in code. This task adds shared mesh/material resources and a 128×128 generated stone tile with a mip chain (about 85.3 KiB of uncompressed RGBA8 texels including mip levels). |
| Particles | No authored particle resources were found. | No baseline particle texture cost. | Wreck smoke/fire emitters are created only for damaged wrecks and use a small generated sphere mesh. |
| Simulation and rendering configuration | 20 JSON files; `models/` contains 3 Python source models, not rendering meshes. | No direct GPU use. | City layout, vehicle dimensions, render streaming, and visual settings configure run-time generation. |

## Renderer and runtime-generated assets

`project.godot` selects Godot's GL Compatibility renderer for desktop and mobile. The view remains the existing orthographic isometric 3D city. Roads, terrain, building footprints, entrances, collision bodies, and navigation continue to come from the actual map data; converting those surfaces to flat sprites would discard existing occlusion, interiors, and collision behavior.

The building system uses generated box geometry, batched window meshes, and a shared, tileable stone facade texture. The new texture is produced once in memory with mipmaps and anisotropic filtering; it does not add a large downloaded texture pack. Character and vehicle meshes are likewise generated and share common geometry/material resources. Runtime GPU memory is therefore reported in the benchmark document rather than guessed from source file sizes.

## Existing import dependencies

- SVG import metadata sets `svg/scale=1.0`, `mipmaps/generate=false`, and `vram_texture=false`; that is appropriate for the small, mostly UI-only icons.
- Warning audio source sizes are not GPU memory. Keep the provenance notes in `assets/audio/warnings/` if audio is replaced.
- Map topology and object placement are data dependencies. Keep road/building source geometry and collision shapes in the simulation-owned map pipeline when importing optional art.
- No source asset was deleted or replaced by this work.
