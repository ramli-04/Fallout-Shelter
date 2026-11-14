# Phase 7: police coordination and organized evacuation

The new `POLICE_SHELTER_EVACUATION` event starts an operation using the existing population, six two-officer police units, patrol vehicles, navigation, traffic rules and atomic shelter admission. It does not spawn civilians, create shelter occupants or move people to demonstrate success. The lowercase API alias `police_shelter_evacuation` is also accepted.

## Test the complete system in the game

1. Open `scenes/main.tscn` in Godot 4.7.2. In **Configure / Social Director**, retain the default 100 agents (65 civilians, 35 authorities). For a full pre-impact evacuation test, turn **Automatic warning** off before starting. Otherwise the existing nuclear countdown can end outdoor operations before a distant patrol or group arrives. Set **LLM agents** to zero for a local-rule-only test; existing asynchronous AI remains supported.
2. Start the simulation. Pan to a populated area, or select a civilian and press **F** to focus the camera. Camera focus supplies the operation's affected-area center.
3. Open the Director settings controls and find **Dynamic Emergencies**. Select **Police Shelter Evacuation**. This selection suggests a 250-unit area and 1,200 simulated seconds so crews have time to travel. Adjust these to the actual area and distances.
4. Leave the target at camera focus, or select S1–S5 as a **destination preference**. For this event, selecting a shelter does not move the affected area to that shelter. Safety, accessible routes, actual capacity and other incoming groups can override the preference.
5. Trigger the emergency. In **Police Dispatch / Roadblock Inspection**, inspect the operation and its individual `EVT` tasks. Watch existing officers assemble, board existing patrol vehicles, travel, park and walk to their assignments. No civilian is enrolled by the trigger itself.
6. Officers physically search, approach people and communicate. Accepted civilians head to the actual gathering marker, then follow an arrived escort. Select a civilian to inspect its group, status and last received order. The police panel shows group members, destination, guide, pending reasons and admissions.
7. While a group is moving, trigger a danger zone or road closure on its route, close its destination shelter, or let unrelated civilians consume shelter places. Inspect new route/destination history and watch the group respond. Existing police roadblocks remain real navigation obstructions; emergency vehicles retain authorized access at police traffic posts.
8. Let the group reach the shelter, or use **Clear last triggered event** for the evacuation event. Completion/cancellation releases civilian membership and returns available crews physically to their patrol. A failed or cancelled operation does not count unresolved people as safely admitted. Pause and speed controls use the existing simulation clock.

The default world is deliberately not arranged to guarantee compliance, available units or a successful route. A pending operation is a legitimate result when conditions do not allow a physical response. Check the pending reason before increasing simulation speed.

## Planning and coordination

`police_evacuation.gd` owns operation plans and dynamic groups. On event start it records the affected area, an initial area/census estimate, a safe gathering location, candidate destination and required roles. That estimate is operational planning information; it does not give civilians orders or track an unknown person's location for an officer.

Small operations request a gathering unit and an escort. Larger ones additionally request intersection security and emergency-access control. Roles have unique task keys, preventing duplicate assignments to the same operation/role. Units share timestamped command briefings, group reports and route revisions. One escort crew serves one group at a time and physically returns to the next gathering group before taking it onward.

`police_response.gd` now accepts non-barrier evacuation tasks through the same assembly, two-officer availability, road-distance ETA, parking, driving, disembarking and walking process used for roadblocks. It does not deploy a barrier for a gathering/escort assignment. Existing roadblock dispatch remains separate and competes for the same actual units. Intersection/access posts can stop civilian traffic and provide route instructions after arrival; emergency services retain passage.

The dispatch path also checks whether a parking approach is obstructed by a stationary vehicle. Stuck progress measures remaining route distance, so repeated small reversing/forward motions cannot indefinitely reset the stall timer. Existing collision-checked reverse and safe pull-over helpers permit an obstructed patrol to continue on foot when a safe exit is available. When it is not safe, the task remains pending instead of moving through the obstruction.

Police may request an operation through `request_by_authority()`. The optional automatic policy uses fresh local perception of at least four civilians plus a local danger or stranded state. It deduplicates pending and active nearby requests and applies a retry cooldown. It does not initiate an evacuation simply because ordinary people are present in a city.

## Consent, groups and movement

Offers require a live police officer within communication range and an unobstructed sightline. A local utility score uses authority trust, cooperation, altruism, fear, aggression, skepticism and situational urgency. Refusals remain independent and are recorded. Later communicated instructions can also be declined after reassessment. Children can follow the consent of a locally visible enrolled guardian.

Each group records members, size, guide, destination, route, movement status, route revision and regrouping position. Compatible waiting groups can merge; capacity pressure can split a larger group by family bundles. Splitting/merging changes membership and instructions, not positions. Family attachment can expand a nominal eight-person group rather than unnecessarily separating a family.

Walking uses the existing free-space route planner and consumes a speed budget from the person's actual position. Group pace accounts for health and fatigue. Followers use visual contact, a following distance and small individual offsets, rather than marching in a rigid formation. The escort waits a bounded time for lagging members. Existing immediate-danger reflexes preempt following; separated people use their last received guide location and can receive local rejoining assistance. Family members can wait briefly for a missing relative.

Only nearby people receive changed orders; seeing a guide can support following, but it does not reveal a remote shelter plan. Existing validated AI movement intentions can leave the group, and explicit pauses are respected. Invalid AI replies cannot detach a person. Agent observations include the person's own group/order and the assigned officer's command briefing in JSON-compatible form. There are no new per-frame inference calls.

Injured members slow the group and generate a medical-assistance report to existing medical personnel when observed by the guide. Confused/frightened people can receive local reassurance. Police do not acquire medical skills, heal casualties or conjure ambulance transport.

## Capacity, threats and admission

Planning considers existing, operational, safe and open shelters with reachable routes. Unknown S5 is not automatically revealed. Pending members count as incoming commitments across all active operations/groups; these commitments are planning estimates, not occupancy changes or hard reservations against independent arrivals.

If available capacity becomes insufficient, the planner chooses another shelter or splits a multi-family group into intact family bundles. A family that cannot fit safely waits. Hazards and roadblocks affect the actual free-space route; a threatened gathering point can be relocated, with new orders delivered through local contact.

Arrival still calls `simulation_manager.admit_arrival()` and `shelter_admission.try_admit()`. A person must reach the real entrance, and the final capacity/safety check remains atomic. An unrelated arrival can consume the last place; no group estimate overrides that admission check.

Operations preserve admitted, refused and uncontacted outcomes and release crews after completion or cancellation. Unavailable units are reassessed and replacement crews must actually travel. Lost crews/vehicles are never moved to fabricate a successful return.

## API and configuration

```gdscript
# Area is independent of optional receiving-shelter preference.
var event_id = manager.add_emergency("POLICE_SHELTER_EVACUATION",
    affected_center, {"radius": 250.0, "duration": 1200.0,
                      "shelter_id": "S2"})

# An authorized officer/commander can request a response.
manager.social.evacuation.request_by_authority(officer,
    "Observed stranded civilians")

# Cancellation retains actual outcomes and initiates crew return.
manager.emergency.clear_event(event_id)

print(manager.social.evacuation.inspection(event_id))
```

`resources/police_evacuation.json` controls planning/instruction intervals, observation thresholds for automatic requests, recruitment duration, cooperation threshold, nominal group size, regrouping/following distances and bounded waits. Existing police crew and vehicle settings remain in their existing configuration files.

Frame recordings contain `evacuation_state` alongside existing police/vehicle/shelter state. Replay restores operations/groups without running their logic; older recordings clear absent evacuation membership. No existing recording format field was removed.

## Modified files and dependencies

| Files | Purpose |
| --- | --- |
| `scripts/police_evacuation.gd`, `resources/police_evacuation.json` | New operation, consent, group, capacity and escort coordinator. |
| `scripts/police_response.gd` | Reuse physical dispatch for task roles; parking-approach checks, progress detection and unavailable-return handling. |
| `scripts/emergency_management.gd`, `emergency_controls.gd` | New event/alias, Director trigger, preference/area distinction and useful defaults. |
| `scripts/social_simulation.gd`, `simulation_manager.gd` | Fixed-clock integration, movement ownership, independent intentions and recording/replay. |
| `scripts/household_travel.gd`, `agent_cognition.gd`, `llm_actions.gd` | Preserve family/safety behavior while coordinating group movement; validate independent departures. |
| `scripts/agent_observation.gd`, `agent_perception.gd`, `authority_coordination.gd` | Private structured context; evacuation is an operation rather than a physical hazard that justifies random roadblocks. |
| `scripts/police_controls.gd`, `object_inspector.gd` | Operation/group/task inspection and individual received orders. |
| `scripts/three_d/social_world.gd`, `agent_3d.gd` | Actual gathering markers and helping/coordination poses; visual observers never move people. |
| `tests/test_police_evacuation.gd`, `test_phase7_ui.gd`, `test_police_evacuation_live.gd` | End-to-end scenarios, edge cases and Director/clock/recording integration. |

Dependency flow: emergency event → evacuation command plan → existing police dispatch → physical communication/consent → group movement → existing atomic shelter admission. Navigation/emergency/shelter changes feed replanning; shared police availability connects evacuation tasks and roadblocks.

## Automated verification

From the project root in PowerShell:

```powershell
$godot = "C:\Users\Moham\Downloads\godot\Godot_v4.7.2-stable_win64_console.exe"
& $godot --headless --path . --script tests/test_police_evacuation.gd
& $godot --headless --path . --script tests/test_phase7_ui.gd
& $godot --headless --path . --script tests/test_police_evacuation_live.gd
```

The operation suite covers all requested scenarios: scattered civilians, several coordinated units, independent shelter arrivals consuming capacity, a new route hazard, refusal, family separation/rejoining, unavailable escort replacement, and actual admissions/crew return. Additional cases cover no safe shelter, cancellation, membership-only splitting/merging, family-preserving capacity splits, shared commitments, invalid AI replies, local authority initiation and pending-request deduplication. The fixture uses existing actors with controlled starting conditions, then production movement/dispatch/admission methods.

The UI suite uses the actual main scene, configuration/start controls, Director event trigger, full fixed clock, gathering marker, police inspector, pause/cancel/resume and recorder serialization. The live suite runs three simulated minutes in the unmodified seeded 100-person city, with no actor relocation or replacement road map; it checks concurrent behavior, patrol dispatch, capacity and exclusive assignments. This is a smoke test, not a claim that the whole operation finishes within three minutes.

Verification results (2026-11-11):

| Suite | Passed checks |
| --- | ---: |
| Organized evacuation scenarios and edge cases | 43 |
| Phase 7 main-scene/UI integration | 11 |
| Seeded 100-person live city | 6 |
| Police response | 39 |
| Phase 6.4 authorities | 33 |
| Phase 6.2 | 1,416 |
| Agent cognition | 31 |
| Dynamic emergencies | 59 |
| Moroccan traffic | 40 |
| Phase 5 UI | 11 |
| Phase 5 | 887 |
| Transport behavior | 8,488 |
| Daily life | 1,881 |
| Daily shelter regression | 13 |
| **Godot total: 14 suites, zero assertion failures** | **12,958** |

The Python cognitive contract suite also passes all seven tests. A final headless editor import reports no script/parse/load errors, `git diff --check` passes, and the local Graphify graph was rebuilt. Engine shutdown notices and existing replay float warnings are listed below; these checks do not establish a warning-free shutdown.

## Known limitations

- This is a walking evacuation system. Patrols carry police; civilian bus convoys, dedicated ambulance pickup and carried/nonambulatory casualties are not implemented here. Medical reporting and speed reduction do not promise professional treatment or transport.
- Gathering search is a bounded deterministic patrol, not perfect knowledge of all civilian locations. Refusals, inaccessible interiors, missing relatives, unavailable units or no safe shelter can leave unresolved people. Recruitment time and the event deadline remain configurable.
- Shelter commitments are estimates, so independent arrivals can still cause redirection. Whole families wait if no safe shelter can fit them; they are not forcibly split to manufacture success.
- Outdoor operations run in LIVING, EVACUATION and BOMB_FALL. The existing nuclear impact/all-clear timing is preserved. New organized outdoor evacuation events are rejected after impact/all-clear; sealed ten-day shelter routines remain their existing system. A terminal scenario is not advanced to pretend that police cleanup happened.
- Animation uses existing procedural action states; this phase imports no new models or animation assets. Headless checks do not establish final visual quality or long-duration performance.
- Existing engine shutdown resource/ObjectDB notices and replay float warnings remain visible. Inspect assertion results and script errors as well as the process exit status.
