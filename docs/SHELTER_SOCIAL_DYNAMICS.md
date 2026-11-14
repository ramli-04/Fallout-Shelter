# Phase 6.7.4 — Shelter social dynamics

The ten-day shelter phase now runs `scripts/shelter_social.gd` through `shelter_life.gd`. It uses an isolated seeded RNG and fixed 15-minute simulated steps. Render frames and network/LLM responses do not advance social time. This is a synthetic behavioral model; its coefficients are tunable design assumptions.

## Relationships and emotions

Each resident stores directed `shelter_relationships[other_id]` with trust, friendship, family attachment, respect, conflict, dependence and cooperation (0–100), plus an interaction count. Existing family/friend links seed priors; interacting updates both directions, while dependence can change asymmetrically. The older scalar friendship field is maintained for compatibility.

Fear, anxiety, stress, morale, loneliness, hope, frustration and sense of safety remain separate resident fields. Family separation, deprivation, unavailable infrastructure and supervision affect them independently. Support and conversation have distinct effects. No combined happiness score is calculated.

## Representation and mutual aid

Adult residents vote after the first simulated hour, then every six hours. Individual preferences combine candidate communication, experience, confidence, cooperation, technical skills, crisis management, and the voter's trust/respect/conflict relationship. IQ is absent from leadership scoring. Candidates can receive no votes; residents may reject all candidates. A leader losing acceptance triggers a challenge and a fresh vote.

Accepted representatives organize voluntary mutual-aid groups with skilled assignments. Task preferences influence ordinary routine decisions; essential needs retain priority. Rejected or departed leaders leave no active work orders. Children receive no medical, security, infrastructure or childcare assignments.

## Disputes and cooperation

Stress, frustration, existing conflict and immediate circumstances generate food, water, sleeping, security, family-protection, leadership and personal disputes. Duplicate open disputes are suppressed. Mediation requires physical presence and willingness; it cannot resolve a resource dispute while acute deprivation persists. Departure closes a dispute without counting it as resolved.

During a meal, a severely hungry adult with low cooperation may take an unauthorized extra serving when stores are scarce and another hungry resident is present. This consumes actual supplies before generating a witnessed theft dispute. `report_incident(actor, other, cause, evidence)` also supports witnessed resource theft and rule violations from other callers, requiring co-presence and a nonempty evidence description.

Completed food distribution conserves shelter stores and can serve children or vulnerable neighbors. Medical assistance and childcare require co-presence. Repairs remain skill-gated. Conversation, organizing, help, protection, sharing and distress support update relationships. Cooperation propensity depends on personality traits, relationship quality, fatigue, stress, family attachment and recipient vulnerability.

## Children and families

Present parents have priority for supervision, followed by trusted empathetic adults with a configurable maximum number of dependents. A sleeping adult does not supervise an awake child. Care requests guide the routine planner toward the child's room without interrupting an in-progress meal, treatment or rest. A requested caregiver counts as supervision only after arrival. Unsupervised children and separation remain visible metrics rather than being silently marked safe.

## Communication and provenance

Co-present residents discuss acquired claims or exchange personal accounts. Relayed claims retain the original source, original acquisition timestamp, original evidence, immediate speaker, relay chain, confidence and acquisition time. Relays are hearsay with attenuated confidence, never direct observation. Conflicting direct observations survive rumors; skeptical listeners can challenge them. Conversation histories and relay chains are bounded by configuration.

## Metrics and audit

`social.experiment_metrics().shelter_social` contains:

- Interaction, relationship-update, cooperation, sharing, care, conversation and rumor-challenge counts.
- Elections, leadership transitions, rejections, challenges, individual ballots, support, groups and tasks.
- Open/started/resolved conflicts, causes and mean resolution duration.
- Seven relationship means and eight emotional means, each reported separately.
- Resident-hours, child-hours, supervised child-hours and separated resident-hours.
- Current and time-weighted supervision rates, and cooperative acts per 100 resident-hours.

No-population means/rates use `null`, not a misleading zero. The director dashboard shows representatives, support and shelter outcomes. The agent inspector shows private emotional state, relationships, caregiver, task and recent conversation provenance. These are director/inspector views, not shared agent knowledge.

The existing append-only social event log includes interactions, elections, disputes, conversations and hourly social metric snapshots. Final experiment metrics and archives include social metrics; archives also include dispute records and individual agent relationship/belief state.

## Verification

Run with the project's Godot executable:

```powershell
& $GodotExe --headless --path . --script tests/test_shelter_social.gd
& $GodotExe --headless --path . --script tests/test_shelter_life.gd
& $GodotExe --headless --path . --script tests/test_daily_shelters.gd
```

The new suite covers 47 checks, including conserved supplies during actual theft, clock partition reproducibility and a complete ten-day routine/room/social integration scenario. It writes `outputs/shelter-social-test-metrics.json` for controlled scenarios and `outputs/shelter-social-ten-day-metrics.json` for the ten-day fixture. These are synthetic test outcomes, not calibrated predictions of real shelter behavior.

Tuning lives in `resources/shelter_social.json`: cadence, election period, acceptance/challenge thresholds, caregiver trust/capacity, conflict pressure threshold and conversation history bounds.
