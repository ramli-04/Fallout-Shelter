# ESSAIM Phase 2.5: living world

> Historical Phase 2.5 guide. The current project implements Phase 2.6 with a
> 3D city and Director-only viewing. Read [PHASE_26_GUIDE.md](PHASE_26_GUIDE.md)
> for current launch/camera/inspection controls; the modeling assumptions below
> still describe the preserved simulation.

Open the **existing** `project.godot` in Godot 4 and press **F5**. No nodes,
signals, plugins, accounts, Python services or API keys need manual setup.
Tested with the installed Godot **4.7.2 stable**. The original main, agent and
shelter scenes, city roads, camera, admission rules and impact effect remain.

## First run

1. Click **Start simulation**. The city clock and nearby conversations run;
   no siren sounds and agents have no evacuation objective yet.
2. Click **Launch nuke**. The siren sounds and agents respond independently.
   This launch has a configurable 2% chance of being a false alarm.
3. Choose **10x** to speed up simulated time. **Pause / Resume** stops and
   continues the same clock, movement, communications and incidents.
4. Click an agent. Scroll the right-hand panel to read its archetype, traits,
   panic, goal, companion, shelter estimates, S5 belief, messages, memories and
   decision history. Inspectors show that person's knowledge.
5. Switch **Observer mode** to **Director mode** to reveal the exact warning
   duration, real/false alarm truth, capacities, stocks and maintenance state.
   This changes presentation only. Observer cards intentionally remain
   unverified; reports are visible in agents' memories and the journal.
6. Select the **Environment** journal tab for observations and incident reports.
   Director mode additionally shows actual incident starts and clearances.
7. A real strike ends with **SHELTERED / EXPOSED** totals and the impact effect.
   A false alarm ends with **ALL CLEAR**, without an impact or exposed agents.

**Reset same scenario** restores the current seed's initial agents, hidden
outcomes and event schedule. Launch at the same simulated time to reproduce the
same trace. **New random simulation** generates and displays a new stored seed.
**Use seed** honors the seed field exactly, including the current value.

The Director-only **False alarm** button forces a fake warning for a demonstration.
It uses the same agent warning as a real launch. This manual button is additional
to the automatic 2% launch chance, not an autonomous environmental event.

WASD/arrows pan the focused map; the wheel zooms; **Fit map** restores the overview.
Blue agents move, green agents are sheltered/safe, gold agents were rejected,
purple agents wait/delay/freeze, yellow agents help, red agents are exposed.
The authority cross remains visible. Map incident rings show active incidents
known through nearby observers, or all active incidents in Director mode.
The **S5 ?** marker is a rumored location in Observer mode, whether or not a real
shelter exists there. Director mode omits the physical shelter when absent.

## Editable assumptions

Stop the game, edit JSON, then press F5 again. Reset uses the loaded configuration;
it does not reread files. Keep backups when experimenting.

| File | Editable data |
| --- | --- |
| `resources/phase1.json` | Seed, population, roles, road positions, speeds, shelter capacities/resources/public descriptions, fixed clock and scoring weights |
| `resources/living_world.json` | Incident and false-alarm probabilities, timing, perception/contact radii, message limits, size estimates, resource assumptions, stress/help/reaction settings |
| `scripts/agent_personality.gd` | Fifteen archetypes' numeric trait means; the JSON jitter and secondary blending produce individual differences |

Shelter truth remains S1 **2500**, S2 **750**, S3 **1800**, S4 **3500**, and S5
**5000 if present**. An absent S5 has zero usable capacity and cannot admit anyone.
Existence is sampled once at initialization, independently of agent count.

S1's stock is **2000 person-days** from its editable shelter definition, enough
for 1000 people for two days. For this prototype, abundant supplies mean nominal
capacity × **10 person-days**; S3's unknown stock is seeded uniformly from
**3600–18000 person-days**. These quantities are hidden from agents. Rats remove
up to **10% × severity** of affected stock once; that loss persists after the
temporary infestation clears. Daily rationing and ten-day survival are not run.

Initial capacity estimates come from public size descriptions: small **600**,
medium **1800**, large **4000**, unknown **2500**, with individual **±30%** error.
These estimates are independent of true capacity. S5 starts at a **50% existence
belief**. Public map risk/resource/popularity information remains in `phase1.json`;
unknown supplies are not interpreted as zero. An observer within **48 world units**
of an entrance can inspect presence, capacity, occupancy, door and visible rats.
This is an explicit prototype assumption about what entrance observation reveals.

Incident probabilities are **per scenario**, each an independent Bernoulli draw:
maintenance **20%** at S2, one eligible door malfunction **8%**, road obstruction
**12%**, crowd **5%**, rats **10%** at underground S2. Each type has at most one
scheduled occurrence per scenario. Seeded starts fall inside **15–80%** of the
warning window, at least **8 simulated seconds** apart; durations are **30–90s**
and severity **0.3–1.0**. Random road/crowd targets are existing central road
intersections. These are provisional game values, not real disaster probabilities.

Maintenance stops admission and lowers condition from 100 to 30 temporarily.
A blocked door rejects arrivals. Travelers physically approaching a road
obstruction wait until it clears. Crowd witnesses gain up to **35 × severity**
panic and penalize routes across that location. Rat witnesses or recipients of
credible entrance reports perceive increased shelter risk. Simultaneous incidents
are combined when refreshing a shelter, so clearing one cannot clear another.

Profiles use all 15 requested archetypes, shuffled across the default 20 people;
trait means receive **±18** jitter and a **25%** optional secondary personality
blend (75% primary, 25% secondary). All traits use **0–100**. Legacy normalized
`trait_range` and the old four `evacuation.personalities` values are retained for
configuration compatibility; Phase 2.5 profiles use the new means and jitter.
Ordinary warning processing takes **0–4s**, aggressive agents halve that delay
and improve their seeded tie priority by 30%. Denial processing takes **18–70s**;
a sufficiently doubted alarm can cause one additional brief stay-home delay.
Overwhelmed agents freeze only above **80** panic, for **8s**, with a **30s**
cooldown; the label alone never causes a stay-home outcome. Panic decays at
**0.04/s**. Helpers within **65 units** may spend **12s** calming a distressed
person by **18** panic points, once per helper/recipient pair. Family-oriented
agents prioritize their designated companion when observed nearby. Leaders
broadcast recommendations; followers weight trusted recommendations and locally
observed crowds; opportunists use a smaller switching margin.

Agent urgency is independently estimated at **360–540s**, then decreases with
the public time since the siren, with a 30s floor. It never uses the true
300–600s impact delay. Hence an agent can wrongly believe a distant destination
is reachable. Distance, resources, estimated capacity, risk, uncertainty, numeric
traits and observations determine scores. Approximate city distance/speed units
are simulation units, not a calibrated real-world evacuation model.

## Information flow and reproducibility

World truth lives in the controller and shelter state. Pure decision logic receives
only a single agent record and that agent's subjective urgency. A dedicated local
perception boundary converts observable state into beliefs; arrival/rejection can
reveal absence or a full entrance. Others learn only by their own observation or
messages. Initial rumors are assigned to five agents without consulting truth.

Contacts occur every **2 simulated seconds** within **110 units**. A speaker sends
at most one new packet per contact cycle. Trust, skepticism, authority trust,
remembered source credibility, hops and existing direct evidence determine
believe/doubt/reject/investigate responses. Direct observation outranks rumor;
a fresh credible observation report can correct a rumor. Messages expire after
**120s**, have at most **4 hops**, and use duplicate suppression. Packet queues,
heard histories and memories are bounded to **30** entries; duplicate bookkeeping
is bounded to eight times the history limit. Current source/reaction/credibility
and original provenance are retained. Rumors can be wrong.

S3's functioning communications equipment repeats only locally deposited
observation packets to agents within **240 units**, with a cache of eight packets.
It never queries other shelters' actual state. This modest relay is a modeling
assumption, not an omniscient authority feed.

Independent seeded RNG streams control S5, profiles, beliefs, warning duration,
alarm truth, supplies and events. Hidden outcomes/schedules are precomputed at
scenario initialization so reset is exact, then activated relative to Launch.
Agent warning estimates use a separate stream from the hidden deadline. The fixed
0.1s clock governs everything; render-frame frequency and display mode do not
change decisions. Replays require the same seed, configuration, launch timing and
engine version; cross-version RNG identity is not promised.

Director **Export trace** writes `user://essaim_trace_<seed>.json`. Its complete
path appears in the Director journal. This includes configuration, truth, agent
decisions/memories and environmental histories; Vector2 values become JSON arrays.
It is a reviewable trace, not a saved-game importer. Export is deliberately a
Director action because it contains world secrets.

## File responsibilities

| New file | Responsibility |
| --- | --- |
| `shelter_state.gd` | Exact capacity, stocks, admission conditions, history and overlapping incidents |
| `environment_events.gd` | Seeded scheduling, actual activation/clearance, road obstruction checks |
| `agent_personality.gd` | Archetypes, heterogeneous 0–100 profiles and initial reaction parameters |
| `agent_beliefs.gd` | Approximate initial knowledge, local observations and bounded memories |
| `rumor_system.gd` | Local packet propagation, interpretation, evidence correction and S3 relay |
| `agent_reactions.gd` | Local hazard/crowd perception, delays, stress recovery, assistance and social observations |
| `world_projection.gd` | Read-only Observer/Director shelter projection |
| `environment_visuals.gd` | Read-only incident map markers |
| `tests/test_phase25.gd` / `render_phase25.gd` | Behavior validation and graphical captures |

Modified scripts: `simulation_manager.gd`, `evacuation_decisions.gd`,
`shelter_admission.gd`, `main.gd`, `dashboard.gd`, `object_inspector.gd`,
`map_view.gd`, `agent.gd`, `shelter.gd`. Previous tests/capture helpers were adapted
to the intentionally changed Start, trait and Observer semantics. Scenes were
preserved. README and historical guide pointers were updated. New JSON configuration
and Godot-generated `.gd.uid` companions are included. Earlier Python scaffolding
remains unused by this game.

## Validate and demonstrate

```powershell
Set-Location 'C:\Users\Moham\OneDrive\Desktop\ESSAIM'
$GodotExe = 'C:\Users\Moham\Downloads\godot\Godot_v4.7.2-stable_win64_console.exe'
& $GodotExe --headless --path . --editor --quit
& $GodotExe --headless --path . --script res://tests/test_phase1.gd
& $GodotExe --headless --path . --script res://tests/test_phase2.gd
& $GodotExe --headless --path . --script res://tests/test_phase25.gd
& $GodotExe --path . --script res://tests/render_phase25.gd
```

All **28 GDScript files** also passed explicit `--check-only` validation, and the
headless editor imported the existing main scene successfully.

Executed results: Phase 1 **1435 checks**, Phase 2 **253 checks**, Phase 2.5
**1093 checks**, each with **0 failures**. Tests cover clock/movement/camera/UI
regressions, capacities and duplicates, seeded schedules and frame partition
replay, hidden-state isolation including exact countdown, local observation,
rumor disagreement/evidence correction/expiry, S3 relay, autonomous incident
consequences/clearance, stress thresholds, false alarms and JSON trace export.
Across **512 fixed seeds**, S5 existed **264 times (51.6%)**; nine false alarms
were sampled; incident counts were maintenance 100, door 37, road 58, crowd 26,
rats 54. This is a reproducible empirical check, not a probability proof.

Graphical captures in ignored `outputs/` show Observer preparation and agent
inspection, Director incidents, real impact, false-alarm all-clear and a
1024×720 window. Captures were rendered by the installed NVIDIA OpenGL driver.
Compilation name conflicts, an encoding issue in the title, one outdated scroll
test and an audio cleanup timing warning were found and corrected during validation.
Check the console as well as exit codes: Godot can exit zero after logging a script
error. No outstanding script/runtime errors were seen in final validation.

For manual incident demonstrations, temporarily set one probability to **1.0**,
press F5, Start, Launch, then select 10x and Director mode. Its onset is scheduled,
not immediate. Use the Environment tab and watch the affected entrance/map ring;
put agents nearby to see who learns about it. Restore original probabilities.
Use Director False alarm to test the all-clear reliably. Reset and repeat at the
same launch time to compare histories. Try an absent-S5 seed (e.g. **2**) and
compare the historical Observer/Director behavior. In current Phase 2.6, use
verified seed **2** and Director's 3D/sidebar inspection instead.

Default capacities greatly exceed the 20-person prototype. To demonstrate full
entrance rejection, temporarily set a capacity to **1** in `phase1.json`, run,
inspect arriving agents, and restore the academic capacities afterward. Unit
scenarios already exercise this boundary. Agents initially retain public size
estimates even when test capacities are altered.

No manual Godot scene edits are required. After an error, copy the exact console
message, seed, JSON edits and reproduction steps. The simulation stops at impact
or all-clear; no ten-day survival, detailed combat, population-scale traffic,
LLMs, Kafka, or Storyteller system has been added. **Phase 3 has not started.**
