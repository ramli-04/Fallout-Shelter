# Driving and streetscape

Start a new game/run to use the updated city. The original seeded road vertices,
connections, carriageway widths, highways and ramps are preserved. Regression
hashes from the previous generator verify this for seeds 42 and 7. Pavements,
markings, buildings and off-road shelter plazas have changed.

## Controls

**CONFIGURE / SOCIAL DIRECTOR → Director** includes:

- **OpenJev overtaking decisions**: enable local model advice for passing choices.
- **Emergency pavement escape (clear paths only)**: permit the last-resort escape.
- **Show accessible building interiors**: inspect the retained physical doors/rooms.

These driving switches persist across resets in the current session. Defaults and
timings live in `resources/traffic_rules.json`. F8 shows vehicle identifiers,
driving reasons, decision providers and the road graph. The selected driver's
inspector also shows speed, speed limit, signal, driving mode and last choice.

## Driving

Ground junctions have phased red/amber/green lights, an all-red clearance interval,
visible signal heads, zebra crossings and stop lines. Signals use simulation time,
so pausing freezes them. Vehicles brake before the line; a bounded movement budget
prevents a large simulation step from crossing a red stop line. Amber permits a
vehicle too close to stop safely to clear the junction. A vehicle already inside
clears rather than freezing when its light changes.

Intersection reservations serialize conflicting movements. Cars yield if the far
side is queued, instead of entering without space to leave. Responding emergency
vehicles receive reservation priority and nearby drivers slow to yield. Emergency
vehicles still obey red lights and physical obstructions.

Vehicles use the actual lane count/width and keep their directional half of the
road. The curb lane is the default. Following considers bumper clearance, relative
speed, braking and a configurable time headway. Drivers slow for turns, parking
approaches, locally visible pedestrians and responding emergency vehicles.

Passing a persistently slow driver is allowed only on a clear adjacent lane in the
same direction, away from junctions and ramps. Checks include front clearance,
fast vehicles approaching from behind, swept vehicle boxes, buildings, pedestrians
and physics occupancy. Normal overtaking into opposing traffic is rejected. Lane
changes take time; the driver checks the corridor while moving and merges back
only when the curb lane is clear.

An imminent collision can trigger a low-speed pavement escape. The pavement must
be wide enough, the approach and escape corridor must be clear, and nearby
pedestrians' possible movement is protected. Bridges, ramps and junction mouths
are excluded. Emergency braking remains available when escape is unsafe.

The planar curb model permits wheel roll-over of a low curb using a raised chassis
clearance (0.32 m) and a visual ride-height adjustment. Collision layers remain
enabled. Tall obstacles, street furniture, wrecks and pedestrians remain physical
constraints. This is a simplified simulation assumption, not a full suspension or
real-world autonomous-driving safety model.

An accident still closes its graph edge for routing. A driver already performing
a validated escape may physically pass outside the obstructed carriageway, then
return when clear. The exception does not bypass police restrictions or barriers.
Other vehicles continue to reroute using their existing acquired information.

## OpenJev

The existing local Laya/OpenJev service chooses between following, braking and a
validated overtaking opportunity. Its state contains only the requesting driver's
speed/limit, local lead speed and gap, visible signal and waiting time. It receives
no hidden accident feed, relatives' positions or other drivers' destinations.

Requests are asynchronous, bounded and share the one-request capacity with daily
spontaneous actions. An eligible passing request can reserve the next slot so daily
actions cannot starve it. Model advice requires the simulation AI master switch
(at least one configured LLM agent); the local controller works in rules-only runs. Replies are revalidated against the current physical scene.
Reset and replay cancel pending requests; wrecked/parked vehicles cannot execute a
late manoeuvre. A local deterministic driving controller provides explicit
`DRIVING_AI` / `RULE_FALLBACK` behavior when model advice is disabled or unavailable.
Immediate collision avoidance does not wait for network inference.

OpenJev uses the existing launcher:

```powershell
./tools/openjev.ps1 start
./tools/openjev.ps1 status
```

The evacuation LLM scheduler and configured model groups retain their existing
behavior. Driving decisions use the versioned `vehicle.driving_decision` event
through the recorder and durable Kafka outbox. Vehicle modes and signal time are
included in replay frames. Existing replay version checks reject recordings from
an incompatible city generator rather than reconstructing them with new buildings.

## Streets and buildings

Ordinary streets now have 4 m pedestrian pavements; Alder Court has 3 m and
mountain approaches 2 m. Road centerlines and carriageways retain their original
size and shape. Stop lines and crossings align with their approach widths.

The default city now contains 200 buildings, including 96 large street-front
parcels, compared with 176 buildings previously. The architecture uses 5–7 storeys,
warm stone bands, tall framed windows, cornices, ground-floor shop frontages and
small iron balconies inspired by the reference photograph. Alder Court retains
its detached houses. Facade details use batched meshes and distance limits.

Rotated local footprints and decorative overhangs fit inside reserved world-space
envelopes shared by placement, pedestrian navigation and collision checks.
Buildings cannot encroach onto carriageways, pavements, parking or bridge decks.
Households, workplaces and important civic buildings retain accessible interiors.

Pole sirens and street furniture use bounded placement attempts checked against
every road and junction, buildings and parking. Roof sirens use the actual building
height. Shelter entrances and rock assemblies occupy reserved off-road plazas;
pedestrian connectors lead from the unchanged road approaches to their thresholds.
Shelter identities, capacities, admission, LLM beliefs and supply systems remain.

## Verification

Focused checks:

```powershell
& $GodotExe --headless --path . --script res://tests/test_traffic_rules.gd
& $GodotExe --headless --path . --script res://tests/test_traffic_openjev_live.gd
& $GodotExe --headless --path . --script res://tests/test_daily_life_world.gd
.\.venv\Scripts\python.exe -m unittest discover -s tests -p 'test_*.py'
./tools/graphify.ps1 build
```

Traffic scenarios cover red stopping/green release, amber/all-red phases,
directional lanes, rear-approach rejection, actual passing progress, pedestrian
vetoes, actual wreck/closure bypass, emergency priority, parking approaches, late
AI replies, reset and off-road siren placement. The live OpenJev test completed a
real Godot → OpenJev → validated `overtake` round trip and cancellation check.

The full 3D scene also checks door geometry, signal mast clearance, visible lights
at every controlled intersection, routine movement and recording. Existing vehicle,
family/transport, indoor spawn, shelter, navigation and configuration checks are
retained. Python discovery runs 68 tests (61 pass, 7 optional skips), including the
original-road hashes, wider pavements, larger buildings and off-road shelter
validation across the existing seed/size/width matrix.

Previews generated by `tests/render_streetscape.gd` are in `outputs/streetscape/`.
They are local generated artifacts, not dependencies of the game.

Final focused results: 198 traffic checks, 1,415 collision checks, 8,487 transport
checks, 885 spawn/capacity checks, 97 navigation checks, 13 shelter checks and 6
configuration UI checks passed. The full scene reported zero failures with 68
indoor starts and no script errors. A short run measured roughly 30 ms median /
47 ms p95 CPU time per simulation step; this is not a frame-rate guarantee.
