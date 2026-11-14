# Phase 6.7.6 — ten-day survival lifecycle

Impact starts Shelter Day 1. The manager advances ten 24-hour simulated days,
then freezes the run and evaluates every original resident and S1–S5. With the
default routine clock rate of 60, one engine second represents one shelter
minute. Reports store simulated seconds, engine seconds and independent UTC
wall-clock timestamps. Day 10 ends at 864,000 simulated seconds.

## Controls

Use the main speed selector or **Configure Simulation → Survival results**:
Pause, Resume, 1×, 5×, 20×, 50× and Next important event. Fast-forward executes
the same one-engine-second steps, stops for event creation/resolution, severity
band changes, deaths or the next daily report. Each render frame processes at most 128
steps and yields after a 12 ms budget (a single step cannot be preempted).
Unprocessed time is retained. High populations can therefore run slower than
the requested multiplier, without skipping simulation work.

Synchronous AI mode waits for pending shelter requests. In asynchronous mode,
network callbacks remain live while the clock advances. Completed shelter
responses received during pause are queued until resume. Responses from old
runs, completed runs, replay or beyond the configured simulation-age limit are
discarded. Speed changes do not change request IDs or wall-clock latency.

## Opening decisions

The Survival results tab lets the Director edit global conditions or overrides
for a selected shelter: minimum day, verified outside conditions, outside hazard
index, maximum accepted hazard, clear route, damaged-structure permission,
electrical requirement and child supervision. Inputs are frozen after final
evaluation and during replay. Preferences persist across simulation resets.

Outside hazard is a **fictional scenario index**, not a radiation model or
medical/safety recommendation. The default outside conditions and route are
unverified; shelters remain closed until explicitly cleared. Destroyed
structures, jammed/blocked doors, physical access restrictions, active fires and
unresolved structural/flood/door incidents prevent opening. A qualified shelter's
door changes to OPEN; residents receive CAN_LEAVE clearance, without teleporting
outside. Children need a living adult caregiver in the same shelter, otherwise
their result is AWAITING_GUARDIAN. Day 10 can end with REMAIN_SHELTERED outcomes.

## Reports and metric definitions

Ten daily reports include living/dead/injured/missing populations; per-shelter
occupancy, food, water, electricity, air and infrastructure; family reunifications;
social metrics and morale; and storyteller history for that day. Final output
contains all daily reports, hourly S1–S5 samples, every agent outcome, family
membership and separation, opening decisions, social conflicts, leadership and
cooperation counts, trust change, maintenance and AI metrics.

- Population is the cohort present at impact. Death is health ≤ 0; injury is
  living health < 100. Explicit MISSING agents and absent original identities
  remain missing rather than being assumed dead. Survivors outside shelters
  remain in the population totals.
- Shelter survival rate follows the arrival cohort even after transfers.
  Occupancy counts living residents currently sheltered. Empty arrival cohorts
  have a null survival rate, not zero. Missing shelters have missing resource data.
- Food uses the existing person-day store. Depletion includes eating, sharing,
  theft and contamination losses. Water is finite: each drink uses up to 0.5 L;
  event treatment for dehydration also requires 0.5 L. A shelter's initial
  `water_liters` truth value overrides the default 20 L per arrival. Repairing a
  pump cannot refill an empty store. These are simplified game rules.
- Infrastructure reliability is the time-weighted mean availability of power,
  air and water. Failure count includes storyteller incidents linked to a
  system; maintenance actions count completed routine technical work. Resolved
  events are reported separately.
- Reunited families have at least two living members in one shelter and no
  missing members; deaths remain visible in their family record. Daily
  reunifications are transitions from the previous day's recorded status.
- AI reports successful responses, failed requests, input/output tokens and
  mean wall latency, plus counted rule decisions from cognition, evacuation
  choices and shelter routines. These count decisions, not unique agents.
  Requests still pending at the end are reported separately; their unknown
  token use and outcomes are not fabricated in the frozen final report.

## Export and replay

Final evaluation automatically writes `outputs/survival-<seed>-<UTC>/results.json`.
The Export button can regenerate it; Open report folder shows the files.
`tools/survival_report.py` produces `report.html` plus seven PNG/SVG charts:
population, food, water, survival rate, stress distribution, family survival
(living family-associated residents) and infrastructure reliability. These
compare S1–S5 from recorded samples. No network access or LLM calls are used.

The game starts chart rendering with `.venv/Scripts/python.exe` when available.
Install the optional dependency with `.venv/Scripts/python.exe -m pip install
".[reports]"`, or render manually:

```powershell
.venv/Scripts/python.exe tools/survival_report.py outputs/<run-folder>/results.json
```

Existing recorded-run playback restores lifecycle snapshots alongside agents,
resources and storyteller events. Replay is read-only playback at recorded frame
resolution (hourly during shelter life), not a fresh stochastic or LLM rerun.
Snapshots preserve opening policies, daily reports, samples and final outcomes.
Simulation reset clears cohort, reports, uptime, samples and final results.

## Verification

```powershell
& 'C:\Users\Moham\Downloads\godot\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script res://tests/test_survival_lifecycle.gd
.venv/Scripts/python.exe -m unittest tests.test_survival_report
```

The lifecycle suite executes the real ten-day routines, checks clock controls,
async pause/resume, event stopping, water conservation, daily boundaries,
population accounting, distinct shelter opening decisions, child supervision,
JSON replay, reset and an empty survivor cohort. Existing shelter life, social
and storyteller suites cover the underlying interactions and emergencies.
