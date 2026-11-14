# Living city and OpenJev

Start the game normally, open **CONFIGURE / SOCIAL DIRECTOR**, and choose the
daily-city settings before starting. **START SIMULATION** runs ordinary city
life. By default, the warning starts after **180 simulated seconds**. The existing
**Launch nuke** control can trigger it earlier. Pause and simulation speed apply
to both ordinary life and evacuation.

The new fields in `resources/social_config.json` are:

| Field | Default | Meaning |
|---|---:|---|
| `pre_disaster_seconds` | 180 | Living-phase duration; zero disables the automatic warning |
| `automatic_warning` | true | Activate the warning after that duration |
| `day_start_hour` | 8 | Local schedule clock at the beginning of a run |
| `routine_clock_rate` | 60 | Schedule-clock seconds per simulated second |
| `spontaneous_actions` | true | Enable asynchronous OpenJev action suggestions |

Schedules represent a simplified weekday morning. Parents and employed residents
commute, children attend school, police patrol, fire/medical staff work at their
stations, and residents shop, visit remembered friend addresses, walk or rest.
Travel consumes simulation time. An activity is not replaced by another scheduled
destination halfway through the trip; arrivals receive a short dwell period.
The schedule clock is compressed independently of physical movement, rather than
claiming to simulate a complete calendar or a validated human behavior model.

## Homes, interiors and spawning

Households receive a shared capacity-checked home in a residential district or
Alder Court. Workplaces and shops use commercial/industrial buildings; civic
staff use their actual school, medical, fire or police building. Starting
locations reflect role, household membership, school status and seeded schedules.
Agents can start inside homes/apartments, workplaces, schools, the medical
station, shops, friends' homes, on sidewalks, driving, or in parked vehicles.

Important occupied/assigned buildings have a lightweight accessible ground-floor
space, floor activity zones, walls, a physical door and an exterior navigation
anchor. **Director → Show accessible building interiors** hides upper floors
for inspection. Upper building volumes remain visible when cutaways are off.
This is one shared accessible floor per building, not a detailed apartment-unit
or multi-floor simulation.

Indoor movement follows a door corridor at the agent's speed before joining
the existing outdoor pathfinder. Entry follows the reverse transition. A warning
during a doorway transition retains enough room state to exit correctly.
Closures can prevent a doorway approach. No transition teleports agents to the
road, and the former school-position reset in each living tick has been removed.

Indoor spawn slots reserve clear positions; sidewalk positions are bounded and
validated. Initial driving cars use lane-aligned swept-box occupancy and Godot
physics queries before leaving their reserved parking bay. Failed placements
are rejected. Ordinary driving uses the existing collision/traffic runtime,
with reserved destination parking and actual approach/exit paths.

## Families and schools

Each household has a leader, member list, shared walking speed and, where a
suitable owner/car exists, a household vehicle. Vehicle selection accounts for
the household's seat requirement. A family without a suitable shared car can
walk or disagree about transport.

Leaders propose shelter/meeting plans through nearby conversation or the existing
phone/message network. Recipients retain their own decisions and can reject a
proposal. Acknowledgements, failed communications and stale remembered locations
have consequences; there is no automatic family location feed.

Accepted members approach and board separately. A moving family car brakes before
boarding. Departure waits for expected passengers. After the configurable timeout,
a low family-priority or explicitly configured leave-behind decision can depart
and records who was left behind. Higher-priority drivers can instead pursue a
missing member's last known location. Seat capacity and physical boarding distance
remain enforced. Passenger positions follow the vehicle.

Walking groups use their slowest member's walking speed. Leaders can wait for
visible stragglers, pause after losing sight, return toward remembered positions,
or continue according to priorities and information age. Reunion is based on
actual proximity and compatible indoor/vehicle/shelter locations. Members never
snap together.

Parents can call children or query school staff using the existing phone system.
Pickup travel uses parking and outdoor routes, then actual school doors. A parent
searches the known room layout until they observe their child; only guardians
can complete pickup. Children can follow staff evacuation instructions until a
guardian is physically present. Congestion, blocked routes, closed doors, stale
messages and competing shelter choices can delay or prevent reunification.

`resources/daily_life.json` controls following distances and boarding/missing-member
waits. The agent inspector shows routine, indoor state, household travel and needs:
safety, fatigue, stress, family concern, health and social attachment. Only the
Director sees aggregate world truth. Observation, local conversation and family
following now respect indoor boundaries, line of sight and sheltered-agent visibility.

## OpenJev

The requested upstream is [razorback16/openjev](https://github.com/razorback16/openjev),
pinned at `b4339c640f5331ef75098637d1be2c787715ee88` (0.7.2). Its supported
**Laya backend** (`laya-1.0`, Laya package 0.3.6) runs on CPU in a separate Python
environment. The 26B DiffusionGemma backend is not required for this integration.
The local endpoint is `http://127.0.0.1:8780/v1/systemone`.

It is installed and running on this machine. On a fresh checkout or after a reboot:

```powershell
./tools/openjev.ps1 install
./tools/openjev.ps1 download  # first setup: pinned public Laya weights, about 804 MiB
./tools/openjev.ps1 start
./tools/openjev.ps1 status
# When finished:
./tools/openjev.ps1 stop
```

The downloader uses resumable ranges and verifies the weight file's SHA-256.
Source, packages and checkpoint stay under Git/Godot-ignored `.tools/openjev/`.
`config/openjev.json` pins source/checkpoint revisions and configures endpoint,
model, request interval, timeout and maximum in-flight decisions. The launcher
binds to loopback; optional API credentials come from `OPENJEV_API_KEY`, not presets.

OpenJev receives only the requesting agent's role, current routine, personal needs
and ages/sources of remembered contact information. It selects from a bounded
role-appropriate menu: continue, rest, contact family, shop, socialize, walk or
drive. Children and duty staff receive smaller menus; high fatigue restricts choices
to a break or family contact. Godot validates the choice and performs ordinary
navigation/boarding; the model cannot issue arbitrary code,
invent coordinates, move relatives or bypass a door or seat limit.

Requests are asynchronous and staggered. The shared evacuation LLM scheduler is
unchanged. Missing/invalid/timed-out OpenJev replies use explicitly labeled rule
fallbacks. Pending suggestions are cancelled at the warning, on reset and when
loading replay, so a late ordinary-life answer cannot override evacuation behavior.
The Director reports OpenJev connectivity, decisions and fallback count.

## Events, replay and verification

Existing recording and Kafka outbox paths carry `building.entered`,
`building.exited`, `routine.changed`, `family.travel_planned`, `family.negotiated`,
`family.left_behind`, `family.boarded`, `school.pickup_started`,
`school.pickup_completed` and `agent.spontaneous_action`. Their versioned backend
allowlist accepts them. Interior state, groups, passengers, routines and needs
are included in replay frames. Reset recreates reservations and household state;
old replay frames without indoor metadata are displayed as outdoor records.

The local AI service was rebuilt with its original Compose overrides and persistent
volumes. All three existing model groups remain connected. A new routine event was
accepted durably by the running backend. Kafka was disconnected before this work
and remains disconnected; actual broker delivery is not claimed.

Run the focused checks from the project root:

```powershell
& $GodotExe --headless --path . --script res://tests/test_daily_life.gd
& $GodotExe --headless --path . --script res://tests/test_daily_spawn_seeds.gd
& $GodotExe --headless --path . --script res://tests/test_daily_life_world.gd
& $GodotExe --headless --path . --script res://tests/test_daily_shelters.gd
& $GodotExe --headless --path . --script res://tests/test_openjev_live.gd # requires local server
.\.venv\Scripts\python.exe -m unittest discover -s tests -p 'test_*.py'
./tools/graphify.ps1 build
```

The tests exercise indoor/driving/parked-car spawning, doorway movement bounds,
obstruction, private information, role-restricted typed actions, boarding/capacity,
braking, deliberate leave-behind, family disagreement, shared navigation,
separation/reunion, actual guardian school pickup, automatic warning and reset.
Additional spawn checks cover seeds 0/2/7 and 400 agents. The current-runtime
shelter suite also verifies capacity/closed-door rejection, hidden sheltered
occupants, indoor LLM/rule planning and reset. Full-scene checks cover
actual door geometry and moving routines; the live OpenJev test verifies a genuine
Godot → OpenJev → executed action round trip. Existing vehicle, social, navigation,
configuration UI, LLM/backend and shelter behavior regressions are retained.

Rendered previews are generated by `tests/render_daily_life.gd` under
`outputs/living_city/`. Graphify's ESSAIM adapter indexes the new runtime modules;
query `daily routines household boarding school pickup` for the updated relationships.

The historical `test_phase1.gd` UI suite still hardcodes the original population,
speed units, outdoor-only spawns and controls. It is not counted as passing
evidence for this feature; `test_daily_shelters.gd` exercises the current shelter
contract separately. No historical UI assertions were weakened to claim a pass.

Validation on this machine (2026-11-08):

| Check | Result |
|---|---|
| City generation and vehicle spawns | 4,107 checks, zero failures |
| City navigation | 97 checks, zero failures |
| Living city behavior | 1,881 checks, zero failures |
| Spawn seeds / 400-agent population | 885 checks, zero failures |
| Current shelter contract | 13 checks, zero failures |
| Traffic rules | 198 checks, zero failures |
| Transport / vehicles | 8,487 / 1,415 checks, zero failures |
| Living city full scene | Zero failures, 68 initial indoor agents |
| Full 53-vehicle scene | Zero failures |

## Performance pass (2026-11-08)

Vehicle perception, collision sweeps and pedestrian checks now use per-step
spatial bins. Static building collision queries use a city obstacle grid, road
segment lookups use a cached segment index, and free-space route cells retain a
bounded cache that is invalidated when road closures change. Route smoothing
checks longer shortcuts first in coarse increments; every selected segment still
passes the obstacle clearance check.

The same living-city full-scene harness measured **5.05 ms median / 14.34 ms p95**
per 0.1-second simulation step after the changes, compared with **28.84 / 46.71 ms**
before the spatial lookups. The 53-vehicle evacuation harness measured **3.16 ms
median / 35.70 ms p95** at 0.05-second advances. Both runs are headless CPU samples;
they do not represent rendered FPS or guarantee performance at larger populations.

The legacy `test_phase2.gd` still expects orthogonal-only paths and older
single-decision timing. It is not counted as current navigation evidence; the
current route-clearance and transport checks above cover those systems.
