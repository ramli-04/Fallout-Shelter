# Street surfaces v2

Generated with the built-in imagegen tool from the user's latest 5-column street,
pavement and public-parking reference sheet. Saved project asset:
`assets/reference_city/street-surfaces-v2.png` (1536 x 1024 RGBA).
The original sheet was not available as a local attachment file; it was supplied
directly to imagegen from the conversation. The derivative is intentionally
orthographic so its road mouths can be connected in the simulation.

Prompt specification used: adapt the reference into an orthographic top-down
1536 x 1024 game texture atlas, five columns and three rows, each tile centered
within its grid cell. Retain charcoal asphalt, white lane paint, double yellow
center lines, warm pale concrete paving, green verges and clipped hedges. Remove
presentation checkerboard, labels, watermarks, cars, trees, poles, vertical
objects and baked cast shadows. Use transparent padding and opaque tile faces.
The requested rows were:

1. Two-lane straight, four-lane straight, zebra-crossing crossroads, top/right
   90-degree corner, top/bottom/right T junction.
2. Broad straight boulevard, four-lane 90-degree corner, four-arm roundabout,
   public parking with six bays per side and a central aisle, flat bridge deck.
3. Seamless concrete slab paving, mid-block zebra crossing, planted promenade,
   planted-median boulevard, single-mouth cul-de-sac turning head.

Road mouths were requested at a common scale; all tiles were requested as flat
squares without isometric perspective. The generated result's actual bounds,
rather than its requested nominal 256-pixel bounds, are recorded in
`resources/street_surface_collection.json`. Runtime applies atlas sampling and
rotations directly without creating duplicated raster crops.
