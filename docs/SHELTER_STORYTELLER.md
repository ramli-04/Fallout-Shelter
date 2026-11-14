# Phase 6.7.5 — Shelter emergencies and storyteller

The existing `environment_events.gd` scheduler creates a shelter storyteller through `shelter_storyteller()`. `shelter_life.gd` owns its lifetime and advances it on the fixed simulation clock. Shelter incidents join the existing `manager.environment_events` stream with `scope: "shelter"`, and use the existing social event recorder, shelter status projection, evacuation policy, and recorded-run player.

The former daily shelter Bernoulli failures are removed. Outdoor events retain their existing scheduler and lifecycle; they cannot independently time out or double-apply a shelter storyteller incident.

## Catalog

| Category | Events |
| --- | --- |
| Infrastructure | Generator failure, electrical short, water pump failure, air filtration failure, ventilation blockage, broken pipes, flooding, fire, door malfunction, communication failure |
| Social | Argument, leadership dispute, food theft, refusal to work, group panic, family disagreement, authority–civilian conflict |
| Health | Injury, infection, respiratory problems, dehydration, exhaustion, medical supply shortage |
| Environment | Rat infestation, pest contamination, underground noises, water contamination, structural damage, temperature change |

Health, contamination and exposure effects are simplified synthetic simulation rules. Event labels describe game conditions; they do not perform medical diagnosis or provide clinical predictions.

## Probability, pacing and state

`resources/shelter_storyteller.json` defines all 29 event types, response skills, work duration, affected systems, room preferences, cooldowns, escalation and shelter profiles. Each shelter has an isolated seeded random stream. Every five simulated minutes, eligible event rates contribute to a probability of `1 - exp(-sum(rates) * elapsed_hours)`, followed by a weighted event selection.

Rates depend on infrastructure condition, reliability, dampness, redundancy, occupancy, stress, supplies, accumulated maintenance work and previous active incidents. Examples: broken pipes increase flooding risk; air failures increase respiratory risk; contamination increases infection risk. Dehydration and exhaustion require the corresponding need pressure. Social incidents require real co-present participants; family and authority conflicts require matching relationships/roles. Work refusal requires an organized task. Food theft requires an actual unauthorized serving from scarce stores; inventory is deducted before a witnessed conflict is recorded.

Default automatic pacing:

- Three-hour warmup.
- At least six simulated hours between incidents in the same shelter.
- At most two automatic incidents per shelter per day and two simultaneously active incidents.
- Type cooldowns of 12 or 18 hours, restarted after resolution.
- Initial automatic severity between 0.15 and 0.45; unresolved incidents worsen slowly, with automatic escalation capped at 0.95.
- A critical incident imposes a 24-hour window of reduced initial severity for subsequent automatic incidents.

Pausing generation prevents new automatic incidents. Existing hazards, consequences, responses and escalation continue. No incident silently disappears when a duration expires; resolution requires actual work and its prerequisites.

Shelter profiles distinguish, for example, a damp metro shelter (S2) from a more reliable, redundant secure facility (S5). Runtime `infrastructure_condition` and `storyteller_profile` dictionaries on shelter truth can supply scenario-specific starting conditions and profile overrides.

## Responses and consequences

Residents learn incidents through physical observation in the event room, or through a report from an actual witness when in-shelter communications work. Reports retain source, evidence, confidence and time. A knowledgeable resident must have a suitable adult role/skill, manageable stress, a reachable work location, and acceptable immediate needs. Relationships influence willingness to assist an injured resident. Ordinary meals, drinking, sleep, treatment and childcare are preserved unless a severe immediate physical hazard warrants interruption.

Assignment starts the existing room navigation and activity animations. Work counts only after arrival, while performing the corresponding activity. Moving residents cannot repair remotely. Progress is proportional to elapsed simulated work, cooperation and stress. Legacy activity completions cannot bypass required work. A blocked entrance can be repaired from its reachable side.

| Response | Prerequisites and effects |
| --- | --- |
| Technical work | Technical skill, physical access and spare parts; restores the affected system and improves maintenance history |
| Fire response | Fire-safety skill and local work; extinguishes the storyteller fire |
| Medical help | Medical skill, local work and medical supplies; treats simplified injury/exposure effects |
| Care | Empathy, contact and potable water where needed; relieves dehydration or exhaustion |
| Supply recovery | Organizing work transfers existing medical reserves into usable stock; no stock is created from nothing |
| Mediation/security | Appropriate cooperation/empathy or security skill; underlying social dispute must actually settle |
| Transfer order | An informed adult commander in contact with residents, an accessible exit, and a verified reachable destination through the existing evacuation policy |

Unresolved fires, floods and structural hazards affect occupants locally. Infection and respiratory events affect their target resident. Pests contaminate a fraction of real food stores. Water contamination removes potable water availability; temperature and noise affect local conditions and emotional state. Communication failure blocks remote incident reports. Door malfunction affects both admission/exit availability and internal door routing.

Completed work can enter `AWAITING_RESOURCES` or `AWAITING_AGREEMENT`; the event remains active and exposes its blocking condition. Technical repairs consume spare parts. Both event treatment and ordinary medical assistance consume medical supplies. Resolution clears only the storyteller's restrictions and preserves independent external emergencies.

## Director testing controls

Open **Configure Simulation → Shelter events** during shelter life.

1. Select shelter, event type and severity; press **Trigger shelter event [MANUAL TEST]**.
2. Select an existing event to inspect its room, severity, work progress, informed residents, responders and complete transition history.
3. Adjust the selected event's severity. The change is audited as a manual action.
4. Pause automatic generation while continuing to test active consequences and responses.
5. Select residents with different roles and try **Test selected resident response**. This requests real movement and work; it does not teleport or grant skills/knowledge.
6. Try a commander transfer request. It is rejected when no verified route/destination or accessible exit exists.

Manual incidents are labeled `origin: "MANUAL TEST"` and `manual: true` in records and controls. They bypass automatic probability/warmup/spacing/daily selection, but retain validation, type cooldowns and the simultaneous-event cap. Controls refuse mutation during replay. Common rejection reasons are shown; denied response tests cannot complete work or change occupancy.

Programmatic controls are available on `manager.social.shelter_life.storyteller`:

```gdscript
var id = storyteller.trigger("generator_failure", "S1", 0.4, true)
storyteller.adjust_severity(id, 0.6)
storyteller.pause_generation(true)
storyteller.request_response(id, technician)
var transitions = storyteller.history
var current = storyteller.snapshot()
```

## Audit, replay and metrics

Starts, assignments, escalation, manual adjustments, pause/resume, transfer orders and resolutions emit typed `shelter.storyteller_*` events through the existing append-only recorder. The shared environment list retains full incident records, including manual origin, participants, room, severity, work, resources blocking resolution and lifecycle flags.

Shelter-phase replay frames are recorded hourly and at finalization. They include the storyteller snapshot in addition to existing agent and shelter state. The snapshot preserves incident/history state, condition and resource pools, pacing, cooldowns, counters, clock and exact RNG state encoded as strings. The existing recorded-run player restores this snapshot in read-only mode; it does not draw randomness, apply damage again or accept director mutations. Playback is state reconstruction, not a promise of resuming a partially replayed simulation.

`social.experiment_metrics().shelter_storyteller` reports automatic/manual incident counts, active incidents, resolutions, escalation notices, work contributions, rejected explicit response requests, transfer orders and event types. Final archives include the complete storyteller snapshot. `outputs/shelter-storyteller-test-metrics.json` contains the test outcomes, a reproducible generated event trace, and ten-day live integration metrics.

## Verification

```powershell
& $GodotExe --headless --path . --script tests/test_shelter_storyteller.gd
& $GodotExe --headless --path . --script tests/test_shelter_life.gd
& $GodotExe --headless --path . --script tests/test_shelter_social.gd
& $GodotExe --headless --path . --script tests/test_daily_shelters.gd
& $GodotExe --headless --path . --script tests/test_dynamic_emergencies.gd
```

The storyteller suite triggers and resolves every catalog type, and covers generation, independently tested daily/active/spacing limits, cooldowns, local consequences, role/location/information/stress restrictions, conserved resources, blocked-door repair, shelter-specific risk, isolated seeds, fixed-clock partition reproducibility, JSON replay, existing recorded-run integration, real controls, commander transfer validation and a full ten-day routine/event run. The prior social suite pauses generation to keep its controlled social fixture isolated from the new event suite.
