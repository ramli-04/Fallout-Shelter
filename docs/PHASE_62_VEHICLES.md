# Phase 6.2 — Vehicle collisions and accident response

The Phase 6.1 road graph and parking layout remain authoritative. Run the game
normally, configure the fleet, then start evacuation. F8 shows vehicle IDs,
health, status and the road graph. The Social Director includes traffic
casualties, secured scenes and recoveries. Wrecks remain visible until recovery.

## Dynamics and spawning

Vehicles use catalog dimensions, capacity, mass, speed, acceleration and braking.
Civilian body styles, police cars, ambulances, fire engines and civil-protection
rescue trucks share the same runtime. Dynamics are planar, with bounded yaw,
route following, braking-distance separation, junction reservations and existing
emergency priority. The existing map has no traffic-light controller. Full
suspension and tire simulation are deliberately omitted.

Spawning searches at most 256 free parking bays in distance order. It expands
oriented vehicle footprints by configurable clearance, checks existing fleet
and reservation footprints with SAT, tests building/rock clearance and queries
Godot physics occupancy. A successful test atomically reserves the bay. Failed
spawns produce no vehicle; collisions are never disabled to accommodate a spawn.
Large vehicles may therefore reduce the fleet below the requested count.
Only generated parking bays are used; arbitrary roadside spawning is not enabled.

The simulation advances vehicle movement in substeps of at most 0.05 seconds.
A spatial hash supplies candidate pairs for continuous swept oriented-box SAT.
Building footprints, roadblocks and pedestrians also receive swept checks.
Godot box casts/intersection queries supplement these against rendered structures,
tree trunks, streetlights, sidewalk and curb surfaces. Bridge clearance excludes
ground-level agents and traffic. Collision stops use time of impact, before damage
and response processing. The method approximates rotation over each substep;
it is not a general rigid-body solver.

Physics layers are bit values: 1 structures, 2 shelter selection, 4 agent
selection, 8 terrain, 16 siren selection, 32 vehicles, 64 vehicle-only street
furniture/curbs/sidewalks. Vehicle world casts query 1 | 64, excluding terrain
and selection Areas. Fleet and pedestrian contacts use authoritative swept
simulation geometry rather than relying on delayed render-node synchronization.
Vehicle proxy bodies use layer 32 and mask 1 | 32 | 64. New furniture collision
layers do not change pedestrian navigation or selection layers.

## Accidents and privacy

Normal relative velocity and vehicle mass ratios determine simplified impact
severity. Stationary impacts use vehicle speed. JSON configuration controls
minimum impact, vehicle damage, occupant damage, pedestrian damage, treatment
rate and recovery delay. These are simulation assumptions, not medically
validated injury or fatality predictions. Injury can reduce health to zero;
dead agents cannot resume walking, board cars or receive restorative treatment.
Random cosmetic accident generation has been replaced by contact-driven crashes.
The explicit `accident()` method remains available for scenario injection.

Accidents leave stationary collision-active wrecks. The road's width and the
wreck's projected footprint determine affected lane indices. The existing A*
graph has one edge per road segment, so routing conservatively closes the whole
edge even when only one lane is obstructed. There is no lane-level passing or
partial-capacity graph yet. Drivers use the existing blocked-route replanning;
no-route vehicles stay stopped. Accident closures never expire on a timer alone.
Other overlapping closures must also clear before an edge reopens. Emergency
vehicles cannot bypass an accident by using the police-checkpoint exemption.

Only nearby observers acquire direct accident knowledge. Dispatch sends an
addressed emergency-system location to an available officer, medic and firefighter.
It does not insert accident beliefs into every civilian's memory. The Director
and replay remain explicitly omniscient. Dispatch currently assumes an available
emergency-system notification; it does not model a failed emergency call.

Responders travel using the existing agent and vehicle routing. Police secure
scenes; medical/fire staff treat nearby living casualties. Available ambulances
can board nearby injured agents and drive them to the Medical Station, where
patients remain under care. Capacity, boarding distance and vehicle damage still
apply. Configured recovery clears secured scenes after the delay, removes wrecks
and reopens the graph. This is a simplified recovery operation, without a tow
truck driving animation. Disable recovery in JSON to retain wrecks indefinitely.

## Events, replay and configuration

Edit `resources/vehicle_physics.json` to change assumptions. Restart or reset the
scenario after changing it. Existing social event recording/outbox carries:
`vehicle.accident`, `traffic.casualty`, `emergency.dispatched`,
`emergency.scene_secured`, `emergency.treatment_started`,
`emergency.evacuation_started`, `emergency.patient_evacuated`, `traffic.recovered`,
and the existing roadblock events. Python's typed event allowlist accepts them.
The existing Kafka bridge publishes accepted events when Kafka is configured;
no separate traffic broker or topic is required. Actual broker delivery was not
verified in this implementation session. Replay frames include accident scenes,
vehicle dimensions, casualties and closure state. Reset clears runtime reservations,
scene assignments and junction ownership before rebuilding the fleet.

## Validation

Run from the project root with the installed Godot 4.7.2 executable:

```powershell
& $GodotExe --headless --path . --script res://tests/test_phase62.gd
& $GodotExe --headless --path . --script res://tests/test_phase5_transport.gd
.\.venv\Scripts\python.exe -m unittest tests.test_social_events tests.test_road_geometry tests.test_city_generator
```

The Phase 6.2 suite covers swept car contacts, buildings, thin barriers,
pedestrians, bridge separation, all-pairs fleet spawn separation, full-bay refusal,
actual Godot occupancy, casualties, dispatch, persistent wrecks, graph closures,
route alternatives, recovery and reset. Existing transport and Python geometry /
event regressions are retained. A headless full-scene startup checks script and
collider integration. Rendered visual quality and sustained large-fleet frame
rates still require interactive validation.

Latest local results: Phase 6.2 **1,415 checks / 0 failures**, transport
**8,487 / 0**, city navigation **97 / 0**, social behavior **849 / 0**,
and Python **13 tests passed**.
The full-scene headless sample retained all 53 vehicles: 120 simulation steps
of 0.05 s measured CPU p50 **5.26 ms**, p95 **49.84 ms**, while other test jobs
were also running. This is a short CPU integration sample, not rendered FPS or
a large-fleet performance guarantee.
