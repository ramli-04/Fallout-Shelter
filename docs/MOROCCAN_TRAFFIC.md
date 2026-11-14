# Phase 4 — intelligent vehicles and Moroccan traffic

The existing vehicle assets, SAT collision solver, population, family travel, authority policies, evacuation admissions and asynchronous inference remain in use. This phase corrects traffic handedness and adds directed vehicle routing and bounded recovery maneuvers.

## Right-hand geometry

`traffic_conventions.gd` defines the shared convention. Simulation XY becomes world XZ. For a unit direction `(x,y)`, its right side is `(-y,x)`. Godot's `Vector2.orthogonal()` has the opposite sign for this map-to-world mapping; the previous positive lane offsets therefore placed moving collision bodies on the left.

The shared right-side vector now determines:

- Initial moving-vehicle placement.
- Vehicle collision-body offsets and lane changes.
- Cruise, same-direction passing, emergency escape and return-to-lane checks.
- Right-side signal placement and safe roadside recovery.

Normal travel uses the outer right lane. Passing uses the adjacent lane toward the center, on the same carriageway, and still requires a clear swept path. `no_overtaking` prohibits it. Pavement escape is restricted to active emergency vehicles with a verified clear envelope. Traffic-light heads face approaching drivers; poles use the approach's right side and do not fall back to the left when space is unavailable.

The baseline keep-right rule was verified against [NARSA's guidance on lane use](https://www.narsa-securiteroutiere.ma/fr/le-non-respect-des-couloirs-de-circulation-et-les-risques-associes/). Intersection/sign terminology is supported by the [Moroccan official bulletin's road-sign specification](https://www.sgg.gov.ma/BO/bo_fr/2015/BO_6332_Fr.pdf). This is a configurable simulation model; existing scenario speed values remain in simulation units rather than being relabeled as statutory limits.

## Directed road-network routing

`vehicle_navigation.gd` constructs an isolated directed routing snapshot from the actual seeded road polylines. It evaluates legal start/end connectors, spline lengths, active closures, authorized emergency access and the driver's recent congestion reports. It never temporarily reconnects or changes costs in the shared pedestrian graph.

| Road metadata | Behavior |
|---|---|
| `direction`: `both`, `forward`, `reverse` | Permitted directions relative to the edge's stored points |
| `one_way: true` | Forward-only shorthand when `direction` is absent |
| `closed: true` | Excludes the edge and its connectors |
| `vehicle_access: false` / `trail: true` | Excludes the edge from through-vehicle routing |
| `junction_control`: `priority_right`, `priority`, `stop`, `yield` | Unsignalled approach control |
| `speed_limit` | Additional per-edge speed cap in simulation units/second |
| `no_overtaking: true` | Disables the passing action |

Unspecified generated roads retain their existing two-way layout. This phase does not arbitrarily convert streets to one-way roads or add roundabouts to the map. Recent known congestion multiplies the relevant road cost by 2.5; reports expire after 30 simulation seconds. The weighted cost applies to complete graph edges and partial entry/exit connectors. A roadblock on the current edge can be avoided by a connector toward its clear end, but a connector cannot cross the obstruction.

Routes recalculate through the existing five-second blocked/congested route checks and through agent cognition's recovery decisions. A new route pointing behind the driver is rejected outside a parking area rather than causing an instantaneous U-turn. Existing parking access maneuvers remain available.

## Intersections and restrictions

Existing green/amber/all-red phases and single-owner junction reservations remain. Vehicles stop at a distance accounting for road width, setback and vehicle length. Amber permits clearing an intersection when braking would be inappropriate. Vehicles already committed clear the junction instead of freezing across it.

Disabled signals use the approach control. The default is priority to the right. A stop approach must stop near its line once per junction visit; a yield approach checks approaching cross traffic; a priority approach does not apply the default right-side yield. Left-turn intent is derived from the route after the junction and yields to approaching oncoming traffic. Existing downstream-space checks prevent entering a blocked intersection. Pedestrian sensing constrains both braking speed and maximum travel before a person crossing the lane.

Metadata-defined stop/yield/no-entry restrictions have reusable procedural roadside signs. Existing zebra crossings, stop lines, traffic-light scenes, road signs and vehicle models are retained. Police barrier visuals and collision geometry now align with the actual road angle; barrier width follows the carriageway width.

## Driver intelligence and accident recovery

The driver remains an ordinary autonomous agent. Phase 3 perception/memory supplies incident evidence; its tactical layer requests recovery. Optional contextual AI receives local driving information, including `country: MA`, `traffic_side: right` and `passing_side: left`. Model calls remain asynchronous and interval-limited. Local validation owns maneuver clearance and physics.

Recovery is a sequence of actual state changes:

1. Existing following, pedestrian, barrier and signal constraints slow/stop the car.
2. Cognition detects lack of forward progress, an observed obstruction, stopped traffic ahead or failure to produce a route. Signal waiting time pauses the obstruction timer.
3. After the configured stall interval, attempt a new route. A backwards route requires recovery rather than an instant heading flip.
4. A stopped, ground-level car may reverse up to 24 simulation units at 8 units/second, after checking its swept body against people, vehicles, barriers, scenery and the physics world. Reversing is rejected near junctions and on elevated roads, ramps or highways. A new obstruction stops the reverse maneuver. Reverse movement does not reset the forward-progress timer.
5. After the abandonment interval, attempt a gradual right-side pull-over at 6 units/second. The parked body's path and the adjacent pedestrian exit point must be clear. Occupants stay in the car until parking completes.
6. The existing `leave()` interface removes actual passenger membership, places people beside the stopped car on clear ground and enables travel on foot. The action is recorded in cognition history. The car remains an actual parked obstruction; it is not deleted or teleported away.

If no safe parking/exit exists, the driver emits an assistance request and reconsiders at a bounded interval rather than reporting a completed exit. Elevated-road exits and unsafe maneuvers remain prohibited. This request is an observable event, not a fabricated tow truck or a promise that physically blocked space will become available. Existing dispatched emergency responders retain their assignment protections.

## Collision-world integration

The previously audited viewport mismatch is repaired. `map_view_3d.gd` binds the current vehicle runtime to its actual world whenever a run is displayed. `vehicle_runtime.physics_query()` uses that world and falls back to the root world in headless/no-view simulations. The reference is weak.

Registered rendered police barriers preserve the existing authorized-emergency exception in shape queries, matching planar checks. Generic obstacles and accident barriers remain solid. A dedicated test verifies that the renderer's independent world is queried, civilians still collide with a checkpoint, and authorized emergency passage uses the intended exception.

## Validation

Godot 4.7.2 tests executed:

| Test | Result |
|---|---|
| `test_moroccan_traffic.gd` | 40 checks passed: five headings, signal facing, actual collision-body lane side, curved-road barrier geometry, one-way routing, congestion/expiry, accident connectors, graph isolation, checkpoint access, bounded reverse, blocked reverse, pull-over, physical disembarkation, priority, signal stops, left turns, pedestrian yielding and world binding |
| `test_phase62.gd` | 1,415 vehicle/collision checks passed |
| `test_agent_cognition.gd` | 31 checks passed, including deterministic simultaneous-agent behavior and rejection of unsafe elevated exits |
| `test_daily_life.gd` | 1,881 checks passed; baseline 68 indoor / 10 initially driving |
| `test_phase64.gd` | 36 authority checks passed |
| `test_phase5_ui.gd` | 6 startup/UI checks passed |

The full-scene sampler completed with 53 vehicles: step CPU p50 11.37 ms / p95 85.73 ms, headless, 0.05-second requested steps during concurrent validation. This is a short CPU sample, not a sustained render benchmark. Existing cleanup warnings remain.

`render_moroccan_traffic.gd` captures an existing initialized moving vehicle and surrounding roads without adding actors or advancing through invented display states. The inspected image is `outputs/phase4/right-hand-traffic.png`. Camera presentation and vehicle assets remain intact. A live model integration soak and comprehensive scenario traffic-capacity benchmark were not performed.

Run with your Godot executable:

```powershell
godot --headless --path . --script tests/test_moroccan_traffic.gd
godot --headless --path . --script tests/test_phase62.gd
godot --headless --path . --script tests/test_agent_cognition.gd
godot --path . --script tests/render_moroccan_traffic.gd --resolution 1440x1000 --quit-after 300
./tools/graphify.ps1 build
```
