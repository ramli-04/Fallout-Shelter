# Phase 6: police dispatch and physical roadblocks

The police response component extends the existing authority, vehicle, perception and emergency systems. The default population remains 65 civilians and 35 authorities. Twelve existing police officers form six units using the six existing police vehicles; the component creates no officers, vehicles or stations. Each unit has a driver, partner, nearest existing station, availability, position, assignment and ETA. Existing daily routines continue between operational assignments.

## Deployment

`authority_coordination.gd` evaluates observed accidents, reported emergency events, nuclear danger and known full shelters. It measures traffic, checks connectivity to shelters and emergency access, selects an actual road segment, and submits a request to `police_response.gd`. Traffic frequency changes the policy threshold; it does not randomly spawn barriers.

Requests retain their operational reason, source event, evidence, segment, responsible unit, barrier ID, pending reason and timestamped history:

`REQUESTED → EVALUATED → ASSIGNED → DISPATCHED → ARRIVED → DEPLOYING → ACTIVE → REMOVING → REMOVED`

Dispatch considers the two officers' health, duty status, other emergency assignments, actual vehicle occupants, parking availability, crew assembly, directed road routes and the final pedestrian approach. ETA includes road travel, congestion known to the driver, crew assembly, walking and deployment time. A nearer station label cannot override a patrol's actual position or reachable road distance. Requests remain evaluated and pending when there is no suitable two-officer unit or deployment capacity.

Officers physically exit buildings, walk to the patrol and board it. The patrol follows existing right-hand traffic, collision, signal and navigation rules to a reserved parking bay. Officers disembark and walk to separate work positions beside the road. Only after both arrive and complete deployment work can the creation API activate a barrier and cones. Access is checked again before activation. Arbitrary `CREATE_ROADBLOCK` actions and direct legacy calls cannot bypass this sequence.

Dispatch pauses ordinary routine movement, family boarding and unrelated AI movement intentions. Existing immediate safety reflexes and authority desertion decisions remain available. A stalled patrol recalculates, attempts a collision-checked reverse, or uses the existing safe pull-over/foot transition. When no safe exit exists, its inspection explains that it is awaiting access clearance; it never teleports through an obstruction.

## Traffic, removal and reassignment

Arrived officers stop approaching civilian vehicles during work and active control. Registered emergency vehicles retain checkpoint access. Deployed barriers update actual road routing and collision geometry. Officers broadcast short-range instructions only across an unobstructed sightline at the same elevation, including to drivers. Instructions identify the officer, request, timestamp, confidence and an adjacent open alternative road when available. Trust influences compliance; cooperating civilians reconsider real routes rather than following an officer into a restricted area. Road closures also affect pedestrian free-space navigation.

Animation states follow actual work: entering/exiting a vehicle, walking, coordinating, placing barriers, deploying cones, stopping vehicles, directing traffic, pointing toward an open route, communicating and removing barriers. Avatars do not move simulation records.

Clearing an operational event initiates removal. Officers walk to the barrier, spend the configured work duration, remove the physical closure, return to the parked patrol and board it before becoming available. Direct removal requests also go through this process. A lost crew leaves the barrier physically present and marked unmanaged while dispatch seeks a replacement; a replacement must travel and take over. Cancellation before departure releases the crew and parking reservation without creating a barrier.

All work uses simulation time and freezes when the simulation is paused. Existing impact/all-clear termination rules are preserved: a stopped scenario retains its last physical state for inspection rather than pretending that cleanup occurred after time stopped. Dead, sheltered or unavailable officers are never moved to fabricate a deployment or cleanup.

## Inspection and configuration

In Director settings, scroll below Dynamic Emergencies to **Police Dispatch / Roadblock Inspection**. The roster lists stations, actual unit locations, vehicles, assigned officers, availability, assignments and ETAs. Choose a request to inspect its reason, measured evidence and complete state history. Active barriers are clickable in the world; individual officers also expose their unit and current action in the agent inspector.

`resources/police_response.json` controls crew size, arrival tolerance, deployment/removal time, dispatch and instruction intervals, instruction radius, concurrent deployment limit and outstanding request limit. The current supported crew size is two; changing the value requires adapting unit construction. Existing vehicle recovery thresholds remain in `resources/agent_cognition.json` and `resources/traffic_rules.json`.

Police state is included in existing frame recordings and restored for read-only replay. Older recordings remain readable without inventing historical patrol assignments. The existing asynchronous AI bridge remains responsible for contextual reasoning; police movement, dispatch scoring and repetitive work use local rules, with no per-frame inference calls.

## Dependency map and verification

`simulation_manager → social_simulation → police_response ↔ authority_coordination`

`police_response → daily_life/building_interiors + road_routes + vehicle_navigation + traffic_rules + vehicle_runtime`

`emergency_management/shelter status → authority evidence → deployment request → physical barrier → navigation/perception`

`police records → social_world/roadblock_3d + agent_3d + police_controls/object_inspector + frame recorder`

Run `Godot --headless --path . --script tests/test_police_response.gd`. The integration fixture uses a controlled road network and existing actors, then production movement to test delayed deployment, missing crews, road-distance ETA, travel, boarding, deployment, crew loss/replacement, collision representation, selection, action animation, instructions, emergency access, physical removal, new assignments, event clearing and snapshot content. Legacy authority/vehicle tests now expect queued police deployment instead of instant barriers; obstruction ownership coverage remains intact using actual accident fixtures.

The headless suite does not establish long-duration performance or replace an interactive visual review. Existing engine resource/ObjectDB cleanup warnings remain visible at test shutdown.
