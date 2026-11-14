# Graphify integration

ESSAIM includes [Graphify](https://github.com/Graphify-Labs/graphify) as an optional
local development tool. It maps the game, Python backend, configuration and
documentation links into a searchable graph. It does not run inside Godot or the
AI service.

The checkout is pinned in `config/graphify.json` to Graphify **0.9.102**, commit
`59b5ab1151e031fb42e39cfc9a50bf96f2d57ae0`. The fetched source and its isolated
Python environment live under `.tools/graphify/`. Its original licenses remain
in that checkout and the installed distribution. The simulation's `.venv` and
requirements are independent.

## Commands

Run PowerShell from the project root:

```powershell
# Already installed here; use this on a fresh checkout to fetch the pinned source.
./tools/graphify.ps1 install

# Rebuild the complete local code graph, including GDScript.
./tools/graphify.ps1 build
./tools/graphify.ps1 open
./tools/graphify.ps1 status

# Query existing graph data without re-reading the entire codebase.
./tools/graphify.ps1 query "vehicle collisions and emergency dispatch"
./tools/graphify.ps1 explain "vehicle_runtime.resolve()"
./tools/graphify.ps1 path "scripts/social_simulation.gd" "scripts/vehicle_collisions.gd"
```

Installation uses the existing project Python to create a separate environment;
if `.venv` is absent it uses `python` on PATH. Internet access is needed for the
initial Git fetch and dependency installation. Build/query operations run locally
without an LLM or API key. The generated HTML uses Graphify's browser visualization
and its external JavaScript libraries; CLI queries remain available without a browser.

The output directory contains:

- `graphify-out/graph.html`: interactive graph with search and node inspection.
- `graphify-out/graph.json`: queryable nodes, edges, provenance and communities.
- `graphify-out/GRAPH_REPORT.md`: coverage, largest files and parser diagnostics.

These outputs and `.tools/` are Git-ignored. `.gdignore` files prevent Godot from
importing the tool checkout or generated graph. `.graphifyignore` excludes
credentials, virtual environments, imported assets and simulation outputs.
Saved experiment recordings and application settings are not modified by builds.

## Godot support and limits

Upstream Graphify does not register `.gd` as a supported language in this pinned
release. `tools/graphify_essaim.py` combines native Graphify code/config extraction
with the GDScript grammar from `tree-sitter-language-pack==0.11.0`:

- GDScript functions, classes, signals and local calls come from the syntax tree.
- Literal `res://` links connect scripts, scenes, resources and configuration.
- Method calls through `preload()`/`load()` aliases connect matching script methods.
- Literal Python module names connect Godot subprocess calls to backend modules.
- Markdown links connect guides to source files; prose is not semantically analyzed.

Explicit declarations and links are tagged `EXTRACTED`. Alias resolution and
Python-module string resolution are tagged `INFERRED`. Dynamically dispatched
calls, runtime signal connections and generated resource paths can remain
unresolved. This is a navigation aid; confirm behavior in the source before editing.

The grammar currently reports a partial parse for `tests/test_city_61.gd`;
the report lists this diagnostic. It is not a Godot compilation failure.
The native extractor also reports no symbols for `pyproject.toml` and the legacy
warning-voice PowerShell script. No cloud/semantic fallback is used for these files.

Use the wrapper's **build** command after changes. Native `graphify update .`
does not invoke the ESSAIM adapter and can omit GDScript from the graph. The
wrapper intentionally performs a complete merge on every build, so deleted
symbols do not accumulate and no manual graph edits are required.

## Coding assistant setup

The official Codex skill is installed at `.codex/skills/graphify/SKILL.md`, with
its upstream reference files. `AGENTS.md` supplies the ESSAIM wrapper commands
and coverage limits. The skill is available to the next assistant turn after
skill discovery refreshes; the PowerShell commands work immediately.
No global assistant configuration or search-blocking hooks are installed.

## Verification

```powershell
./.tools/graphify/venv/Scripts/python.exe -m unittest tests.test_graphify_integration -v
./.tools/graphify/venv/Scripts/python.exe -m pip check
./tools/graphify.ps1 build
./tools/graphify.ps1 query "vehicle collisions"
```

The adapter tests cover AST calls, scene links, Python bridges, comments and
strings, shadowed aliases, sensitive/external path rejection, legacy Windows
text encoding, parse diagnostics and stable symbol IDs. They skip cleanly in
the main simulation environment when the optional parser is not installed.
