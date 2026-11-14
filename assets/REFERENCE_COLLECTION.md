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

Ground now uses only the plain green turf region, with a soft grass texture and
consistent green tint matching the user's lawn reference. Dirt/flower/bush biome
bands are disabled. Playable and background terrain share this unshaded material
and matching perimeter heights; the overview terrain is no longer lowered below
the surrounding ground. Blast-zone outline rings are hidden by default and remain
available through the Director checkbox.

`resources/building_art_scale.json` defines a single width for each current artwork,
with a 2.1 m human doorway as the scale reference. Sprite height follows its aspect
ratio. Parcel dimensions no longer stretch artwork. Detailed buildings, overview
batches and reusable prefabs use the same registration. These are visual reference
scales; they do not replace the existing interior/collision layouts.

Vehicle dimensions come from model definitions, never per-instance dimensions.
The same imported SUV always has the same dimensions, including its SWAT variant.
Unavailable van, truck, hatchback and motorcycle assets use distinct procedural
bodies instead of stretching a sedan or SUV into another vehicle class.

Roads now partition the actual connected asphalt geometry into complete, disjoint
junction and segment surfaces **before triangulation**. Their UVs follow each road's
axis and cumulative path distance. T junctions and all four corner directions come
from graph connectivity, not node ID or a triangle's nearest road. Two-road bends
receive filled corner surfaces and curved center markings. The supplied atlas
provides asphalt and lane detail; painted perspective curbs inside junction pictures
are suppressed because the game's physical curb follows the actual street edge.
Both detailed chunks and the overview use these road surfaces. Off-map tunnel
scenery remains disabled. New road geometry is rebuilt automatically on startup.

Police and fire use the parking painted into their building art. Extra asphalt,
parking lines, parking signs and accessibility/loading decals are suppressed for
these two stations. `scripts/station_parking.gd` registers six police bays and three
fire-apron bays to artwork UV positions, reserves them for their respective fleet,
and supplies departure aisles. Police includes marked cars and dark SWAT SUVs;
fire bays accept fire engines only. Painted apron pixels receive ground-plane depth
so they cannot hide the real vehicles. These are visual simulation vehicles, not
traffic baked into the station image.

Validation: `tests/test_road_art_layout.py`, `test_fixed_art_dimensions.gd`,
`test_sprite_registration.gd`, `test_station_art_parking.gd`, `test_parking_departure.gd` (also accepts
`-- police` or `-- fire`), `test_visual_streaming.gd`, and
`test_road_ground_collection.gd`. `render_station_aprons.gd` captures both stations
and the map edge into `outputs/` for visual inspection.

Regenerate categorized resources after changing atlas regions:
`godot --headless --path . --script res://tools/organize_reference_assets.gd`
Restart to refresh loaded visuals. No new map generation is required.


Current street sheet (latest user reference)
------------------------------------------

`assets/reference_city/street-surfaces-v2.png` is a built-in-imagegen adaptation
of the newest supplied street sheet. The original isometric presentation was
adapted into 15 orthographic top faces to avoid baking perspective trees, lamps
and raised tile sides into the road mesh. This is a prepared derivative, not a
pixel-exact extraction. Roads, pavements and public parking now use this atlas;
the prior atlas remains the grass source. Building artwork is unchanged.

`resources/street_surface_collection.json` lists the native AtlasTexture cutouts;
individual resources are `assets/Roads/current_*.tres`. Regenerate them with
`godot --headless --path . --script res://tools/organize_street_surfaces.gd`.
Straight streets, broad roads, planted medians, intersections, T junctions,
normal/wide corners, roundabouts and turning heads use corresponding top faces.
Public parking uses the painted left bay bank and central aisle, registered to
its existing six simulated bays and actual parcel orientation. The second bank
is omitted because those lots contain one simulated bank; no decorative extra
parking spaces are advertised. Police/fire integrated parking remains unchanged.

The new atlas supplies yellow center lines, white edge paint, zebra crossings,
curb ramps, concrete slab paving and parking bay paint. Old generated crossings,
parking outlines and public-parking ground decals are suppressed to prevent double
paint. Existing street vegetation and lampposts remain separate world objects.
See `assets/reference_city/STREET_SURFACES_V2.md` for generation provenance.


Garage storage and visual repair
-------------------------------

There are at most three `new_parking` garage buildings. The remaining industrial
buildings use the current office artwork. Garage art, scale and colors are unchanged.
`scripts/vehicle_garages.gd` selects garage sites deterministically and assigns at
most twelve civilian-owned cars to each (36 maximum across three garages). Cars
start stored, without a visible mesh or collision footprint. Owners walk to an
entrance-side waiting point; the car spawns only when the shared exit and merge
are clear. Cars returning during daily routines are stored again. Ownership,
storage and departure fields are recorded in existing replay frames.

Police/fire fleets retain their station bays. Their exit now stays reserved until
the departing vehicle clears the street merge, and they are not randomly placed
on roads during initialization. Surface parking artwork remains unchanged.

Ramps now have atlas asphalt, edge paint and concrete edge strips instead of a
flat gray ribbon. Their height follows the endpoint grades, and vehicles use the
same grade. Highways retain six lane markings in both detailed and overview views.
Billboard trees are kept clear of elevated decks and ramps to avoid sliced crowns.

Checks: `test_garage_storage.gd -- physics`, `test_parking_departure.gd -- police all physics`,
`test_parking_departure.gd -- fire all physics`, `test_daily_life.gd`, and
`test_visual_streaming.gd`. Existing ObjectDB shutdown warnings are unrelated.

Garage-side green slivers from an adjacent atlas hedge are clipped out without
changing the garage artwork. Assigned parking exits can cross their driveable
pavement surfaces while still colliding with walls, trees, poles and vehicles.
At most one owner per garage can start a routine departure at initialization;
these cars still spawn through the same checked exit instead of on random roads.
