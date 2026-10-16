# Seeded city and terrain

The scenario seed now generates street spacing, building footprints, building
heights and forms, forest placement, and the reserve's hill location. Use the
existing Settings seed input and **Apply seed**, or **Random**, to generate
another city. Resetting with the same seed reproduces the same geography.

- Central Park occupies a large continuous rectangle near the map center, with
  trees, curved walking paths, a recessed reservoir and the S1 refuge.
- The northeast quarter is a protected green reserve. S5's rumored site is on
  its approximately 32-metre hill. Its original probabilistic existence and
  private-information rules remain in effect; the reserve exists either way.
- The rest of the city has rolling ground and a lower western ridge. Larger
  irregularly sized blocks contain L-shaped apartments, courtyard buildings,
  commercial podiums and stepped towers with varied heights and colors.
- Streets use uneven seeded spacing. Buildings share blocks instead of each
  having a separate surrounding street. Nature paths curve between junctions.

`scripts/city_map.gd` owns the layout and route graph. The simulation regenerates
it before creating agents and shelter beliefs, so displayed shelter locations,
spawn points, private maps and destinations agree. Civilians now use free-space
navigation across clear ground; the street/path graph is no longer a mandatory
walking route. Buildings and the reservoir remain obstacles. Generated shelter sites
replace the legacy input coordinates in `resources/phase1.json` for each run.
Existing shelter capacities, availability, memories, sirens and nuclear mechanics
continue to use the existing simulation systems.

Terrain is a triangulated height field with a matching collision surface.
Buildings, avatars, shelters, markers and camera focus sample terrain elevation.
Roads and paths are shaded onto the terrain itself to prevent overlapping ground
surfaces from flickering. Instanced vegetation limits rendering overhead.
Simulation movement remains fixed-clock and measures planar route length; slope
does not introduce a new speed or physical climbing model.

Run `tests/test_procedural_map.gd` with headless Godot to verify seed reproducibility,
reserved green areas, shelter locations, clear spawns, building-free routes,
navigation geometry and terrain collision. `tests/render_procedural_map.gd`
produces overview, park and hill PNGs under `outputs/` using the actual renderer.
Earlier Phase 4 performance results describe the previous map; rerun experiments
before comparing evacuation outcomes on this larger, more varied geography.

A pre-change snapshot of scripts, scenes, resources and configuration is saved
at `outputs/checkpoints/pre-procedural-map.zip`.
