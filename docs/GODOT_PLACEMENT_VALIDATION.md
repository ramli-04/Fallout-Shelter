# Godot logical placement validation

The existing deterministic road/layout worker remains the generation source.
`CityMap.load_layout` now independently runs `scripts/generation/building_validator.gd`
before hydrating runtime records or creating building scenes. Failed loads return
false with `generation_error`, preserving the previous map state. The existing
world worker continues its bounded deterministic generation retries upstream.

The validator uses separate spatial hashes for building envelopes and road
corridors. Polygon intersections reject overlapping interiors while accepting
shared boundaries. Rect2i broad-phase envelopes, rotated-footprint envelopes,
parcel containment, entrance road connections, unobstructed access strips,
service reservations and graph connectivity are checked in logical map units.
It prints a report and stores it in `CityMap.validation.godot`.

F8 toggles `ParcelDebug` in the existing 3D city scene: green parcels/access,
red invalid footprints, blue roads, yellow reserved service sites, and orange
inaccessible access paths. Existing map-coordinate conversion is reused. No
scene editing is required. Rejected layouts are never instantiated, so their
invalid geometry is available from the validator report rather than displayed
as a completed city.

Known scope: service reservations are dedicated parcels, not yet whole road-
bounded municipal blocks. Citywide block subdivision and parking garages remain
outstanding. The legacy layout path uses clear nearest-road checks when saved
records lack explicit frontage; new records carry explicit access paths.
