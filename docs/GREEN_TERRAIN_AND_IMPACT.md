# Green terrain, vegetation and impact

The GROVE lawn slabs were removed from city_details.gd. Continuous terrain uses
muted dark green grass with subtle seeded variation, including parks, mountains
and shoreline land. Roads and built surfaces keep their existing materials.

New generated worlds target 1,800 trees per reference map area (previously 260),
scaled by the vegetation setting. Tree spacing now uses nearby spatial hash
cells rather than checking every prior tree. Buildings, road corridors, parking,
municipal circulation parcels and entrance paths are excluded. Existing saved
worlds keep their recorded tree inventory; regenerate to obtain the new density.
Legacy maps without recorded terrain also receive additional scattered trees.
Foliage continues to use chunked MultiMesh batches without per-tree processes.
Environment cache inputs include the vegetation revision.

At impact, the radius covers the furthest corner from the epicentre. Existing
severity and shelter resistance still determine damage; map coverage does not
force all shelters to be destroyed. The visual wave reaches its radius in 5.5
seconds, dust in 6.5, and all presentation processing stops after eight seconds.
The ground wave keeps its vertical scale instead of growing into a tall torus.

Performance changes: spatial tree spacing checks, lazy F8 debug mesh allocation,
and street-detail updates at 10 Hz. No measured FPS improvement is claimed.

Validation: test_world_generation.py and test_map_impact.gd. Inspect
outputs/reference-neighborhood.png for the updated terrain palette.
