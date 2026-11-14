extends SceneTree
const Grid=preload("res://scripts/generation/chunk_grid.gd")
func _initialize() -> void:
	var grid:=Grid.new()
	assert(grid.world_to_cell(Vector2(79,79))==Vector2i(1,1))
	assert(grid.cell_to_chunk(Vector2i(-1,30))==Vector2i(-1,1))
	assert(grid.reserve(Rect2i(0,0,2,2),"building","A"))
	assert(not grid.reserve(Rect2i(1,1,2,2),"building","B"))
	assert(grid.reserve(Rect2i(2,0,2,2),"building","B"))
	assert(grid.reserve(Rect2i(0,0,2,2),"building","A"))
	assert(not grid.place_decoration(Vector2(10,10),Vector2i.ONE,"tree"))
	var data={"version":1,"tile_size":40,"chunk_tiles":30,"chunks":[{"coordinate":[0,0],"entities":["building:0"],"owned_entities":["building:0"],"layers":{}}],"entities":[{"id":"building:0","kind":"building","tile_origin":[1,1],"footprint":[2,2],"owner_chunk":[0,0]}]}
	assert(grid.load_manifest(data)); assert(grid.entities.size()==1)
	var invalid=data.duplicate(true); invalid.entities[0].owner_chunk=[1,1]; assert(not grid.load_manifest(invalid))
	assert(grid.load_manifest(data)); assert(grid.entities.size()==1)
	assert(grid.validate_buildings([{"rect":[50,50,60,60]}]))
	assert(not grid.validate_buildings([{"rect":[0,0,200,200]}]))
	print("Chunk grid: footprint rejection, ownership, reload and coordinates passed"); quit()
