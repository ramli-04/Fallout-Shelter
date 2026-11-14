# Categorized reference collection

The existing lowercase `assets/` and `scenes/` roots are retained for compatibility
with the project and Linux exports. Windows cannot host separate `Assets` and
`assets` directories. The requested categories are now available:

- `assets/buildings/Houses/`
- `assets/buildings/Apartments/`
- `assets/buildings/Police/`
- `assets/buildings/FireStations/`
- `assets/buildings/Offices/`
- `assets/buildings/Parking/`
- `assets/Nature/Trees/`
- `assets/Nature/Bushes/`
- `assets/Nature/Grass/`
- `assets/Roads/`
- `scenes/ReferenceAssets/` with matching reusable visual prefabs.

The `.tres` cutouts are Godot AtlasTexture resources, usable directly by Sprite2D
or Sprite3D. They share one PNG rather than duplicating pixels. Some tightly packed
illustrations have overlapping rectangular bounds; the provided scenes and live
renderer apply cutout masks to remove neighboring artwork. The scene prefabs are
flat image meshes compatible with the existing map renderer, not reconstructed
solid buildings. Existing colliders and simulation footprints remain separate.

`resources/reference_collection.json` stores the 26 regions and categories.
`assets/reference_city/neighborhood-nature.png` is a transparent AI-edited
preparation of the user's newly supplied sheet. Built-in imagegen was used to
remove the checkerboard and presentation labels while preserving the original
composition and detailed illustration style. Prompt: preserve the 1536x1024
layout and every object; replace only checkerboard/background/labels with alpha.
The result is a prepared derivative, not a claim of pixel-exact extraction.

The live map now selects buildings exclusively from this latest collection: all
five house variants, apartments, police, fire, offices and the parking garage.
Medical and school roles use the latest office art with their existing POI labels.
Previous building sheets remain on disk for old recordings and developer resources,
but are no longer selected for live buildings. Trees, shrubs, fences and road props
remain individually addressable atlas resources; no large reference sheet is pasted
into the world.

Ground repeats at **0.5 x 0.5 rendered metres**, using all 13 supplied ground regions
with a shared restrained green palette. Playable ground and the surrounding terrain
share the same material. Mip filtering reduces distant texture shimmer. Off-map
highway surfaces and their tunnel/rock scenery are no longer drawn.

Police and fire use the parking painted into their building art. Extra asphalt,
parking lines, parking signs and accessibility/loading decals are suppressed for
these two stations. `scripts/station_parking.gd` registers six police bays and three
fire-apron bays to artwork UV positions, reserves them for their respective fleet,
and supplies departure aisles. Police includes marked cars and dark SWAT SUVs;
fire bays accept fire engines only. Painted apron pixels receive ground-plane depth
so they cannot hide the real vehicles. These are visual simulation vehicles, not
traffic baked into the station image.

Validation: `test_station_art_parking.gd`, `test_parking_departure.gd` (also accepts
`-- police` or `-- fire`), `test_visual_streaming.gd`, and
`test_road_ground_collection.gd`. `render_station_aprons.gd` captures both stations
and the map edge into `outputs/` for visual inspection.

Regenerate categorized resources after changing atlas regions:
`godot --headless --path . --script res://tools/organize_reference_assets.gd`
Restart to refresh loaded visuals. No new map generation is required.
