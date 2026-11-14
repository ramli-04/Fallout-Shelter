## graphify

This project has a local knowledge graph at `graphify-out/`. Graphify is an
optional development tool; the game and inference service do not depend on it.

The upstream skill is installed at `.codex/skills/graphify/SKILL.md`. These
ESSAIM-specific commands override its generic install/build/update commands:

```powershell
./tools/graphify.ps1 install
./tools/graphify.ps1 build
./tools/graphify.ps1 query "vehicle collisions and emergency dispatch"
./tools/graphify.ps1 explain "vehicle_runtime.resolve()"
./tools/graphify.ps1 path "scripts/social_simulation.gd" "scripts/vehicle_collisions.gd"
```

Rules:
- For architecture and relationship questions, query the existing graph with the
  wrapper before broad source exploration. Verify relevant source before editing.
  Use ordinary source searches if the graph is absent, stale, incomplete, or does
  not answer the question. Do not use graph output as evidence of its own correctness.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `./tools/graphify.ps1 build`. Do not use native
  `graphify update .`: it does not support GDScript and would omit the adapter's edges.
- Builds are local and do not call LLMs. Keep `.env`, dependencies, imported assets,
  simulation outputs and tool checkouts excluded. Semantic/cloud extraction needs
  a separate explicit user request.
- Outputs and the isolated `.tools/graphify` environment are ignored by Git and
  Godot. Do not add generated graphs or dependency files to version control.
