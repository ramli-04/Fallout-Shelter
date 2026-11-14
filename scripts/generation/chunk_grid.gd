extends RefCounted
## Persistent logical tiles; visuals can unload without releasing reservations.
var tile_size:=40.0
var chunk_tiles:=30
var chunks: Dictionary={}
var entities: Dictionary={}
var occupied: Dictionary={}
var decorations: Dictionary={}
var error:=""
func world_to_cell(point: Vector2) -> Vector2i: return Vector2i((point/tile_size).floor())
func cell_to_chunk(cell: Vector2i) -> Vector2i: return Vector2i(floori(float(cell.x)/chunk_tiles),floori(float(cell.y)/chunk_tiles))
func world_chunk(point: Vector2) -> Vector2i: return cell_to_chunk(world_to_cell(point))
func chunk_world_size() -> float: return tile_size*chunk_tiles
func bounds(record: Dictionary) -> Rect2i:
	return Rect2i(Vector2i(int(record.tile_origin[0]),int(record.tile_origin[1])),Vector2i(int(record.footprint[0]),int(record.footprint[1])))
func cells(rect: Rect2i) -> Array[Vector2i]:
	var result: Array[Vector2i]=[]
	for x in range(rect.position.x,rect.end.x):
		for y in range(rect.position.y,rect.end.y): result.append(Vector2i(x,y))
	return result
func can_place(rect: Rect2i,layer: String="building",owner: String="") -> bool:
	for cell in cells(rect):
		var key:=str(cell)
		if occupied.get(layer,{}).has(key) and occupied[layer][key]!=owner: return false
	return true
func reserve(rect: Rect2i,layer: String,owner: String) -> bool:
	if not can_place(rect,layer,owner): return false
	if not occupied.has(layer): occupied[layer]={}
	for cell in cells(rect): occupied[layer][str(cell)]=owner
	return true
func owner_chunk(id: String,point: Vector2) -> Vector2i:
	if entities.has(id): return Vector2i(int(entities[id].owner_chunk[0]),int(entities[id].owner_chunk[1]))
	return world_chunk(point)
func load_manifest(data: Dictionary) -> bool:
	chunks.clear(); entities.clear(); occupied.clear(); decorations.clear(); error=""
	if int(data.get("version",0))!=1: error="Unsupported tile manifest"; return false
	tile_size=float(data.tile_size); chunk_tiles=int(data.chunk_tiles)
	if tile_size<=0 or chunk_tiles<=0: error="Invalid tile dimensions"; return false
	for record in data.chunks:
		var coordinate:=Vector2i(int(record.coordinate[0]),int(record.coordinate[1]))
		chunks[coordinate]=record
	for record in data.entities:
		var id:=str(record.id); var rect:=bounds(record)
		if entities.has(id) or rect.size.x<1 or rect.size.y<1: error="Invalid tile asset: "+id; return false
		var owner:=Vector2i(int(record.owner_chunk[0]),int(record.owner_chunk[1]))
		if not chunks.has(owner) or id not in chunks[owner].owned_entities:
			error="Missing chunk owner: "+id; return false
		for x in range(floori(float(rect.position.x)/chunk_tiles),floori(float(rect.end.x-1)/chunk_tiles)+1):
			for y in range(floori(float(rect.position.y)/chunk_tiles),floori(float(rect.end.y-1)/chunk_tiles)+1):
				var coordinate:=Vector2i(x,y)
				if not chunks.has(coordinate) or id not in chunks[coordinate].entities:
					error="Missing cross-chunk footprint: "+id; return false
		entities[id]=record
		if record.kind=="building" and not reserve(rect,"building",id): error="Overlapping building tiles: "+id; return false
	for coordinate in chunks:
		for layer in chunks[coordinate].layers:
			if layer=="building": continue
			if not occupied.has(layer): occupied[layer]={}
			for local in chunks[coordinate].layers[layer]:
				var cell: Vector2i=coordinate*chunk_tiles+Vector2i(int(local[0]),int(local[1]))
				occupied[layer][str(cell)]=layer
	return true
func place_decoration(point: Vector2,footprint: Vector2i,id: String,building_owner: String="") -> bool:
	# Stable ownership lets a streamed chunk rebuild an existing decoration.
	var rect:=Rect2i(world_to_cell(point),footprint)
	for layer in ["building","road","access","parking"]:
		if not can_place(rect,layer,building_owner if layer=="building" else ""): return false
	if not reserve(rect,"decoration",id): return false
	decorations[id]=rect
	return true

func validate_buildings(records: Array) -> bool:
	var count:=0
	for id in entities:
		if entities[id].kind=="building": count+=1
	if count!=records.size(): error="Tile manifest building count mismatch"; return false
	for i in range(records.size()):
		var id: String="building:%d"%i
		if not entities.has(id): error="Missing building tile footprint: "+id; return false
		var tile_bounds:=bounds(entities[id]); var r=records[i].rect
		var physical:=Rect2(float(r[0]),float(r[1]),float(r[2]),float(r[3]))
		var reserved:=Rect2(Vector2(tile_bounds.position)*tile_size,Vector2(tile_bounds.size)*tile_size)
		if not reserved.grow(.01).encloses(physical): error="Building exceeds N x M tile footprint: "+id; return false
	return true
