# Logical tiles and chunks

Generate a new world to enable the chunk manifest. Historical saves keep their
geometry and load through the existing compatibility path.

`resources/chunk_generation.json` defines 40 simulation units per tile (4 m),
30 x 30 tiles per chunk, and asset module dimensions. Thus a chunk spans 1200
simulation units (120 m). A standard road module is 2 x 2 tiles. Wide roads and
long street runs consist of multiple modules. Buildings have individual N x M
footprints computed from their entire reserved envelope, including rotation.
Tiles represent placement space; they do not change agent movement units.

The road graph and terrain are still planned globally first, so districts and
streets connect across boundaries. The parcel generator now reserves a sparse
occupancy grid and rejects candidates whose cells are already reserved. The
complete saved manifest contains every chunk, including empty chunks, stable
chunk seeds, asset footprints, and separate building, road, parking, reserved,
access, tree and prop layers. This is a logical grid over the existing geometry;
it does not convert the road network into a Godot TileMap or independently draw
random street networks in each chunk.

Each entity has one owner chunk and references in every chunk it touches.
Godot's ChunkGrid validates ownership, bounds and building-cell collisions
before runtime scene instantiation. Streaming uses the authoritative chunk
size and building ownership. Unloading visual nodes never releases logical
occupancy. Rebuilding a decoration with the same ID is idempotent. New roadside
furniture uses logical cell reservation in addition to geometry clearance.

The manifest is deterministic and saved in the world JSON. Loading chunks in
another order does not re-roll assets. Chunk seeds are available for future
local generation; the current layout is generated up front, then streamed.
Cell reservations are conservative: a rejected footprint is skipped rather
than forced onto a neighboring parcel. Existing bounded world retries remain.

F8 displays the logical tile lattice, chunk boundaries and parcel outlines.
New-world console output includes chunk count, asset count and tile dimensions.
Generation cache keys include the grid configuration.

Validation: test_tile_world.py (cell collision, edges, cross-chunk references,
empty chunks, deterministic manifests and real building/road occupancy),
test_chunk_grid.gd (runtime rejection, ownership, negative coordinates, reload),
test_world_generation.py, and test_visual_streaming.gd.
