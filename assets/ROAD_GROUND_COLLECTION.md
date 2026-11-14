# Road and ground atlas

`assets/reference_city/roads-ground.png` is a prepared transparent derivative of
the user's latest road/grass sheet. Built-in imagegen was used to remove only the
checkerboard, section labels and presentation watermarks while retaining its
layout and detailed artwork. The source canvas is 1254 x 1254. Prompt: preserve
all tile designs and positions; replace background/labels with true alpha; no
rearrangement. The selected generated source was
exec-40ae7c94-6027-40b9-b9a6-36bfd64c711a.png.

`resources/road_ground_collection.json` records 26 road assets and 13 ground
assets, their crop rectangles and affine top-face sampling coordinates. Godot
AtlasTexture resources are categorized under `assets/Roads/` and
`assets/Nature/Grass/`. Existing earlier-sheet damage/parking resources remain
available for compatibility. Export with tools/organize_road_ground.gd.

Live roads sample this atlas on the existing terrain-constrained road triangles.
Two/four-lane roads use separate source artwork. Junction topology selects T,
crossroad, corner, end and roundabout families; road connectivity and collisions
remain determined by the original road graph. Special bus/cycle/turning tiles
are exposed as library assets rather than arbitrarily enabling bus/cycle lanes
without transport rules. Pavement is sampled from the same road sheet.

Grass uses actual atlas top faces, excludes raised soil sidewalls, and blends
seven base styles with six sparse decorative ground variants. Selection is
seeded and continuous across chunks, and mip levels adapt to screen footprint.
The old noise-based color-only grass shader is no longer the live grass source.
Ground-illustrated rocks and shrubs are decorative textures, not new obstacles.

Restart to refresh loaded materials; existing saved maps work without a new
layout. Tests: test_road_ground_collection.gd and the existing render, alignment,
source-art and streaming checks. Preview: outputs/new-road-grass-atlas.png.
