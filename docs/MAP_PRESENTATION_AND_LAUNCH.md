# Map presentation and launch

The main menu offers seed selection, generation, resume, scenario settings and
quit. Escape returns to the menu (or closes an open drawer first). Initial launch
waits for a user choice before generating a city.

The loading screen shows weighted completion of real pipeline stages: terrain,
districts, shelter reservations, layout, environment, infrastructure and
validation occupy 0?70%. Scenario and presentation handoff reaches 85%; initial
visible-chunk preparation reaches 99%; 100% is shown only when ready. Progress is
published atomically by the Python worker and polled by Godot. Cached stages may
complete immediately. This is work-stage completion, not a time estimate.

New generated layouts reserve a roadside motel and its own parking before
ordinary development. Detached house artwork is capped at 11 x 10 m, with a
14 x 12 m cap for the largest house; authored proportions are preserved within
the registered footprint. All visible building entrances receive 1.8 m paving, registered to the artwork contact position;
legacy cul-de-sac driveways receive paved borders. Logical entrance paths remain the navigation authority. Back and side property fences
use wood, white and chain-link sheet artwork while keeping entrances clear.
Dense downtown/mixed residential roads use 8 m sidewalks with the larger paving
slab region; regular streets retain their normal sidewalks.

Parking paint is drawn from actual bay records as open U-shaped bays rather than
stretching a three-space tile over a six-space lot. Accessible and service/loading
reference tiles are placed in their own bays. Aisles, vehicle routes and departure
serialization remain the driving authority. Post-impact road damage uses the
reference damaged-road/pothole tiles. Straight and curved roads retain their
terrain-constrained surfaces and junction graph; the reference asphalt supplies
the surface artwork. This does not replace the connected graph with pasted tile
screenshots.

Grass now uses continuous seeded patches of lush, dry and sparse grass, inspired
by the requested survival-game look. It is original procedural shading, not an
extraction of Project Zomboid game files. Detail fades with distance to avoid
noise and shimmer at overview zoom. No animated noise is used.

Generate a new world for the guaranteed motel, widened sidewalks and new
reservations. Tests cover seeded generation, tile footprints, menu startup,
worker progress through scenario preparation, parking departures, asset bounds,
and shader rendering. Existing resource/ObjectDB shutdown warnings remain.
