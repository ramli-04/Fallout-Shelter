# Reference architecture and parking repairs

The supplied building sheets guide the live 3D renderer. The implementation uses
original procedural geometry, not pasted sprites: brick/stone apartment blocks
with balconies, glass office grids, suburban pitched roofs, fire-engine bays,
police/medical/school signage, rooftop ventilation and entrance planting.
All windows are intact. Floor spacing and glazing belong to a single facade;
the former imported/procedural window overlap is removed.

`reference_architecture.gd` batches trim, glazing, railings and equipment by
material. Masonry has a shared procedural brick shader; its opacity works with
building occlusion fading. Existing lot footprints, wing shapes, interior doors,
cutaway views and persistent physical obstacles remain authoritative. Civic
buildings use a single coherent two-storey envelope. Overview proxies share the
new palette; close views show detailed roads without the overlapping overview
ribbon. The map viewport uses 4× MSAA and neutral daylight.

Characters now initialize their bone poses from the rest skeleton. This fixes
the collapsed body/limbs seen in the screenshot. The existing animation system
uses the corrected rig, with rounded torsos and age-dependent proportions.

Parking departures reserve a shared aisle until reaching the road. Their exit
waypoints survive congestion replanning, lane offsets remain zero throughout
the driveway and parking speeds are capped at 1.8 m/s. Collision stops restore
route progress, so a stopped car does not continue toward a skipped waypoint.
Actual impacts still cause damage; collisions are not disabled in parking lots.

After alerts, seeded driver temperament, stress and risk tolerance affect speed
and following gaps. Some drivers ignore red lights and priority rules. Variation
is stable over simulation time rather than new randomness every frame. Pedestrian
perception, braking, physical collisions and obstacle sweeps remain active.
Imminent-collision pavement escape is available to civilians as well as emergency
vehicles only when the existing clearance checks succeed.

The runtime now accepts the generator's version 4 maps while retaining version
1–3 compatibility. Previously generation could succeed but loading failed with
an empty error message.

Verification scripts:

- `tests/test_parking_departure.gd`: two cars physically exit an occupied generated
  lot without crashes, shared aisle ownership and deterministic alert behaviour.
- `tests/test_traffic_rules.gd`: ordinary signals, alerted noncompliance, following,
  pedestrian braking, overtaking and emergency escape.
- `tests/test_phase62.gd`: actual swept impacts, casualties, dispatch and recovery.
- `tests/test_rendering_architecture.gd`: bone separation, animations, resources,
  vehicle rendering and reversible masonry fading.
- `tests/test_visual_streaming.gd`: full generated-world streaming and occlusion.
- `tests/render_visual_repairs.gd` and `tests/render_reference_neighborhood.gd`:
  render inspectable PNG previews into `outputs/`.

Restart the game or regenerate the world to rebuild existing building visuals.

## Modeled reference buildings (current)

The image billboard experiment has been replaced. All building shells now use
`reference_architecture.gd`: actual wall volumes, intact framed glass, masonry,
parapets, pitched house roofs, apartment balconies, rooftop ventilation and
entrances. Their geometry follows the parcel rotation and participates in the
game's lighting, depth and shadows. Reference images guide the design rather
than being pasted into the scene. Overview buildings are solid lit boxes with
procedural facade windows, never camera-facing image quads.

Fire stations have red garage doors, glazing, bollards and a separate tall wing
when the structural recipe permits it. Police stations have a stone entrance
and badge. Medical stations use a 22 m tower with glazing and medical signage.
Structural wings and persistent collisions share `building_shape.gd`; buildings
with accessible interiors retain their existing interior layout and cutaway.
Agent occlusion fading is still intentional and reversible.

`tests/test_modeled_buildings.gd` checks that building geometry has real depth,
uses the appropriate architecture, follows parcel rotation, and matches collision
wing counts. The visual repair gallery includes a medical tower preview.


## Current: 2D building artwork

Building exteriors now use pre-rendered transparent PNG sprites rather than live
wall/window/roof meshes. `tools/bake_building_sprites.gd` produces 32 images (eight
archetypes and four facings) in `assets/building_sprites/`. These are rendered from
the game's stylized designs, not cropped reference photos. `building_sprites.gd`
shares textures/materials, selects the nearest parcel-facing direction, and sizes
artwork to the structural recipe. Distant views use batched sprite quads too.

This changes building presentation; the existing 3D scene, physics, navigation,
camera, and optional interior cutaway remain. Artwork has baked lighting and
cannot show arbitrary new sides as a continuously rotating 3D model would.
The four parcel-facing images are chosen when the building is loaded. Restart
the game to refresh existing exterior nodes. Regeneration is not necessary.

Sprite depth correction: the shared sprite shader sorts at the near footprint edge so foreground terrain cannot erase ground floors. `tests/test_sprite_ground_depth.gd` compares rendered lower-wall pixels with terrain hidden and visible for both close sprites and overview MultiMesh sprites. This is a presentation sorting bias; physical footprints remain unchanged.


## Sprite alignment audit

The sprite library now includes 72 parcel orientations per archetype (5 degree
steps), replacing four right-angle images. Camera yaw changes select matching
views, including overview batches. Maximum orientation quantization is 2.5
degrees at the default isometric pitch. Width and height use the same scale so
roof edges preserve their projected angles; the anchor uses the baked height.
Arbitrary camera pitch still changes the relationship between fixed artwork and
the ground projection. Continuous pitch-matched sprites are not provided.

Civic sprites were revised using the supplied reference sheets as design guides:
fire garage bays and tower, police service annex, hospital wings, emergency
canopy and helipad. They remain stylized recreations, not exact image copies.
The earlier street-sheet atlas continues to supply signs, fences and furniture.
PNG mipmaps reduce shimmer when zoomed out. Assets are loaded on demand and
shared by material key. Rebuild artwork with tools/bake_building_sprites.gd;
restart the game to refresh an existing scene.

Verification: test_sprite_alignment.gd checks all 576 image resources, frontage
quantization, uniform scaling and camera-facing selection. The ground-depth
render regression checks close and overview sprites. The neighborhood and civic
gallery renders were inspected under the Compatibility renderer.

White-quad hardening: sprite materials share a single Shader resource. Texture lookup retries null cache entries, checks imported resources, falls back to the same archetype facing zero, and finally supplies a transparent texture rather than an unbound white sampler. Active fade copies follow their source material when camera-facing artwork changes. test_sprite_texture_loading.gd loads and checks alpha for all 576 resources and checks shader sharing/null-cache recovery.


## Livelier streets and follow camera

Single-click agent selection now enables follow, including inspector/list agent
selection. Manual keyboard or drag panning cancels it. Focus movement uses an
analytic damped spring, with a tiny capped deceleration sway that settles to zero.
Snap/reset clears motion. Camera updates remain presentation-only.

The sprite baker now includes small/larger detached houses, townhouse rows,
low-rise apartments and motels, with porches and garage doors in house artwork.
The prepared reference sheet supplies additional street furniture: bins,
recycling, mailboxes, bus stops, bicycle racks, utility poles, bollards, manholes,
drains, plus white/chain fences, gates and stone/concrete walls. Placement is
seeded by stable building index and respects roads, footprints, parking and
recorded access strips. Decorative furniture does not introduce new colliders.
The existing geometric road network and functional signals remain authoritative;
reference road tiles are not pasted across the driving surface.

Tests: test_smooth_follow_camera.gd covers smooth focus, moving targets,
frame-rate consistency, rest and reset. Sprite-resource and depth tests cover
new artwork. Asset sheets guide recreations; this does not claim every pixel or
alternate view from the supplied sheets appears as a separate placed object.


## Current: reference-sheet artwork throughout the map

The reference-sheet style now replaces the simplified baked building library.
Actual atlas regions from streets.png supply nine small house variants, a large
house, duplexes, townhouses, apartments and both motel types. Office artwork
comes from the earlier civic sheet. Civic services use civic-detailed.png, an
AI-edited/derived atlas prepared in built-in imagegen mode from civic.png and
streets.png, preserving detailed brick/stone/roof textures. Prompt: three separate
police/fire/hospital front-angle cutouts, faithful detailed isometric material
style, transparent background, no captions, parking slabs or vehicles. This is
derived reference art, not an exact extraction of the newer civic illustration.

Roads now sample complete two/four-lane road tile artwork, including lane paint,
and parking samples the sheet's parking tile. UVs are computed along the real
road network on its existing terrain-constrained triangles; no additional
floating road strips or collision changes are introduced. Sidewalks use the
actual paving tile at full strength. Crosswalks retain existing geometry.
Hedge segments and existing signs, fences and furniture use reference cutouts.
The camera pitch is 30 degrees for a 2:1 ground projection. Buildings use the
sheet's native view and mirrored frontage directions, not 72 synthetic views.
They cannot show arbitrary unseen sides; camera orbit remains disabled as before.

Restart to rebuild loaded visuals. No new world generation is required for this
art change. Tests: test_reference_art_integration.gd, test_sprite_alignment.gd,
test_sprite_ground_depth.gd. Preview: outputs/reference-art-final.png.


## Ground registration correction

Each sheet archetype now has a projected ground-depth profile. The image contact
centre is registered onto the parcel centre, instead of treating the sprite's
bottom edge as the property centre. Artwork occupies 85% of the available
projected envelope, leaving margin for baked stairs and planters. Close and
batched overview sprites use the same placement data. The forward depth sorting
bias was reduced to avoid drawing sprites over distant foreground objects.

Intersections now sample plain asphalt from the sheet instead of magnifying
cropped turn arrows. Four-lane tile UV axes are swapped because that source tile
was drawn in a different orientation from the two-lane tile. Crosswalk geometry
and physical road surfaces remain authoritative. Rendering and contact-centre
regressions: test_sprite_ground_depth.gd and test_sprite_registration.gd.
