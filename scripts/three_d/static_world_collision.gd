extends Node3D
## Persistent physics is independent of visual chunk residency and fading.
const Map=preload("res://scripts/city_map.gd")
const Shapes=preload("res://scripts/three_d/building_shape.gd")
const C=preload("res://scripts/three_d/world_coordinates.gd")
const G=preload("res://scripts/three_d/geometry.gd")
var trees: Array=[]
var buildings: Dictionary={}
var doors: Array=[]
var destroyed: Dictionary={}
func _ready() -> void:
	name="PersistentWorldCollision"
	var terrain:=StaticBody3D.new(); terrain.collision_layer=8; terrain.collision_mask=0
	# Match the render terrain's exact diagonal and clipped border triangles.
	var vertices:=PackedVector3Array(); vertices.resize((Map.terrain_columns+1)*(Map.terrain_rows+1))
	for y in range(Map.terrain_rows+1):
		for x in range(Map.terrain_columns+1): vertices[y*(Map.terrain_columns+1)+x]=C.to_world((Vector2(x,y)*Map.terrain_cell).min(Map.MAP_SIZE),0)
	var faces:=PackedVector3Array(); faces.resize(Map.terrain_columns*Map.terrain_rows*6)
	var cursor:=0
	for y in range(Map.terrain_rows):
		for x in range(Map.terrain_columns):
			var i:=y*(Map.terrain_columns+1)+x
			for offset in [0,Map.terrain_columns+2,Map.terrain_columns+1,0,1,Map.terrain_columns+2]: faces[cursor]=vertices[i+offset]; cursor+=1
	var mesh:=ConcavePolygonShape3D.new(); mesh.set_faces(faces); mesh.backface_collision=true
	var shape:=CollisionShape3D.new(); shape.shape=mesh; terrain.add_child(shape); add_child(terrain)
	for index in range(Map.lots.size()):
		var recipe: Dictionary=Shapes.plan(index)
		var root:=Node3D.new(); root.position=C.to_world(Map.lots[index].get_center()); root.rotation.y=Map.lot_angles[index]; root.set_meta("building_index",index)
		add_child(root); buildings[index]=root
		var solid:=StaticBody3D.new(); solid.collision_layer=1; solid.collision_mask=0; solid.set_meta("building_index",index); root.add_child(solid)
		for box in Shapes.boxes(recipe):
			var body: StaticBody3D=solid
			if box.door:
				body=StaticBody3D.new(); body.collision_layer=1; body.collision_mask=0; body.set_meta("building_index",index); root.add_child(body)
				doors.append({"body":body,"room":recipe.interior,"index":index})
			var collider:=CollisionShape3D.new(); var box_shape:=BoxShape3D.new(); box_shape.size=box.size
			collider.shape=box_shape; collider.position=box.position; body.add_child(collider)
	var details=preload("res://scripts/three_d/city_details.gd").new()
	details.signal_placements.clear(); details.light_placements.clear()
	details._build_signals(self); details._street_lights(self); details.free()
	for item in trees:
		var s: float=item.scale
		G.collider(self,Vector3(.5,2.8,.5)*s,C.to_world(Map._v2(item.position))+Vector3.UP*1.4*s,64)
	for item in Map.prop_data: G.collider(self,Vector3(.8,.55,.8),C.to_world(Map._v2(item.position))+Vector3.UP*.275,64)
func _process(_delta: float) -> void:
	for entry in doors: entry.body.collision_layer=0 if destroyed.has(entry.index) or entry.room.get("door_is_open",false) else 1
func apply_damage(records: Array) -> void:
	for index in buildings:
		if index>=records.size() or records[index].destruction_state=="INTACT": continue
		destroyed[index]=true
		for body in buildings[index].get_children():
			if body is StaticBody3D: body.collision_layer=0
