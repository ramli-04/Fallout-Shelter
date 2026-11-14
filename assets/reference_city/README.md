# Reference city artwork

## Current use

Buildings no longer use these image atlases. They are recreated as lit mesh
architecture in `reference_architecture.gd`, with physical depth, roof details,
window frames, balconies and civic signage. Distant buildings also use solid
geometry. The atlases remain for street furniture and subtle road surface detail.
The description below records the earlier, superseded building sprite approach.

These atlases are derived from the two reference sheets supplied by the user.
They were prepared using built-in image generation/editing: remove the baked
checkerboard and sheet headings/captions, preserve individual objects, and adapt
the office tower with MEDICAL CENTER signage. The civic sheet received a second
transparency cleanup. They are AI-edited derivatives, not exact pixel extractions.

- `civic.png`: 1536 x 1024; fire station, police station, medical tower, apartments.
- `streets.png`: 1312 x 1199; homes, apartments, motel, paving, signs and furniture.

Prompt intent: preserve the supplied isometric designs and their atlas positions;
remove only presentation backgrounds and labels; keep normal intact windows;
add medical signage to the office tower. No downloaded asset pack was used.

Runtime atlas regions live in `scripts/three_d/reference_sprite_catalog.gd`.
Buildings and furniture use camera-facing 2.5D artwork. This preserves the supplied
image appearance but does not reconstruct rotatable 3D models. Existing collision
geometry, entrances, vehicle routes, traffic light states and interior cutaways
remain simulation geometry. Roads retain connected meshes and markings, using
subtle surface detail sampled from the reference sheet. Fences are decorative and
placed away from roads; they do not introduce new navigation obstacles.

Detailed and distant buildings share the same atlases. Material fading duplicates
only the affected material, then restores the shared resource. Restart the game
or regenerate the map to refresh visuals already loaded in a running session.

Validation: `tests/test_reference_artwork.gd`, `tests/test_visual_streaming.gd`,
and `tests/render_reference_neighborhood.gd`.


Current replacement: building exteriors again use the actual prepared sheet art,
including nine houses and street/road/paving/parking regions. The previous
"Current use" section above describes an earlier implementation. civic-detailed.png
is the selected built-in imagegen derivative from civic.png and streets.png:
three separate detailed civic buildings, matching source material textures,
transparent background and no presentation labels or ground slabs. The generated
source file is exec-3bb955d1-5158-4550-ba0e-fa20bf6a2aeb.png. Roads are UV mapped
onto authoritative road meshes, not a screenshot laid over terrain.
