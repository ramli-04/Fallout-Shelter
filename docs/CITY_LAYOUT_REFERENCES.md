# City layout references

Original procedural geometry inspired by public Cities: Skylines II player layouts. No game assets, save files or player telemetry are imported.

- https://www.reddit.com/r/CitiesSkylines2/comments/1956m83 — downtown grids and curved residential neighborhoods.
- https://www.reddit.com/r/CitiesSkylines2/comments/1rbh2gd/my_first_real_try_with_road_hierarchy_critique/ — connectivity and arterial spacing.
- https://www.youtube.com/watch?v=sV9g1CmU5NE — St. Joseph player build: realistic grids and road hierarchy.

Shared row and column offsets preserve aligned frontage. Connected local blocks feed spaced arterials and boulevards. Organic layouts bend at district scale; radial layouts retain rings and spokes. Protected land, shelter reservations, planar noding and reachability validation remain authoritative.

Generate a new city for version 11 geometry. Saved worlds retain their stored layouts.


## Generator placement correction (version 12)

Removed terrain-grid deep-block infill. Ordinary buildings now come only from
road-frontage candidates, with recorded road entries, entrance paths, rotated
footprints and parcel polygons. Access strips are reserved against subsequent
buildings; rejected placements are left empty. Residential frontage uses smaller
90?130 by 85?120 simulation-unit footprints and one/two-story heights.

Police, hospital and fire facilities are created before ordinary development,
with separately reserved service sites and dedicated parking. The fire station
retains the historical `offices` parking category for runtime compatibility.
Sites reserve circulation land as well as building volume. These are dedicated
service parcels; converting them into complete four-road municipal blocks is
still outstanding, as is full block polygon subdivision across all districts.

Validation checks stored parcels, road-entry connectivity, blocked access paths,
service-site encroachment and existing road/building/parking collisions. AABB
navigation envelopes remain conservative around rotated polygon footprints.
The generator version invalidates cached layout artifacts. Existing saved worlds
retain their recorded geometry; generate a new world to use the new placement.
