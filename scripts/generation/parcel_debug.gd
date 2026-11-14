extends Node3D
## Toggle with F8. Logical polygons are transformed by the existing world mapping.
const Map=preload("res://scripts/city_map.gd")
const C=preload("res://scripts/three_d/world_coordinates.gd")
const Validator=preload("res://scripts/generation/building_validator.gd")
func _ready() -> void:
	name="ParcelDebug"; visible=false

func _build() -> void:
	_draw_grid()
	var report: Dictionary=Map.validation.get("godot",{})
	for i in range(Map.building_data.size()):
		var record: Dictionary=Map.building_data[i]
		var color:=Color.RED if i in report.get("invalid_indices",[]) else Color.GREEN
		outline(Validator.polygon(record.parcel) if record.has("parcel") else Validator.rectangle(record.rect),color)
		if record.has("municipal_block"): outline(Validator.polygon(record.municipal_block),Color.YELLOW)
		if record.has("access_path"):
			var points:=Validator.polygon(record.access_path)
			line(points,Color.ORANGE if i in report.get("inaccessible_indices",[]) else Color.GREEN,false)
	for road in Map.roads: line(road.points,Color.DODGER_BLUE,false)
func outline(points: PackedVector2Array,color: Color) -> void: line(points,color,true)
func line(points: PackedVector2Array,color: Color,closed: bool) -> void:
	if points.size()<2: return
	var mesh:=ImmediateMesh.new(); mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in range(points.size() if closed else points.size()-1):
		mesh.surface_add_vertex(C.to_world(points[i],1)); mesh.surface_add_vertex(C.to_world(points[(i+1)%points.size()],1))
	mesh.surface_end()
	var node:=MeshInstance3D.new(); node.mesh=mesh
	var material:=StandardMaterial3D.new(); material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED; material.albedo_color=color; material.no_depth_test=true
	node.material_override=material; add_child(node)
func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_F8:
		if get_child_count()==0: _build()
		visible=not visible; get_viewport().set_input_as_handled()

func _draw_grid() -> void:
	if Map.tile_grid==null: return
	var mesh:=ImmediateMesh.new(); mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var step: float=Map.tile_grid.tile_size
	for x in range(0,ceili(Map.MAP_SIZE.x/step)+1):
		mesh.surface_set_color(Color(0.6,0.7,0.8,.35)); mesh.surface_add_vertex(C.to_world(Vector2(x*step,0),1)); mesh.surface_add_vertex(C.to_world(Vector2(x*step,Map.MAP_SIZE.y),1))
	for y in range(0,ceili(Map.MAP_SIZE.y/step)+1):
		mesh.surface_set_color(Color(0.6,0.7,0.8,.35)); mesh.surface_add_vertex(C.to_world(Vector2(0,y*step),1)); mesh.surface_add_vertex(C.to_world(Vector2(Map.MAP_SIZE.x,y*step),1))
	mesh.surface_end()
	var node:=MeshInstance3D.new(); node.mesh=mesh; var material:=StandardMaterial3D.new(); material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED; material.vertex_color_use_as_albedo=true; material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA; material.no_depth_test=true; node.material_override=material; add_child(node)
	for coordinate in Map.tile_grid.chunks:
		var size: float=Map.tile_grid.chunk_world_size(); var p: Vector2=Vector2(coordinate)*size
		outline(PackedVector2Array([p,p+Vector2(size,0),p+Vector2.ONE*size,p+Vector2(0,size)]),Color.YELLOW)
