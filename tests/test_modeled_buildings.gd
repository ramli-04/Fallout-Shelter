extends SceneTree
const Map=preload("res://scripts/city_map.gd")
const Building=preload("res://scripts/three_d/building_3d.gd")
var checks:=0
var failures:=0
func _initialize() -> void: run.call_deferred()
func check(value: bool,label: String) -> void:
	checks+=1
	if not value: failures+=1; printerr("FAIL: "+label)
func inspect(node: Node) -> void:
	if node is MeshInstance3D: check(node.mesh is QuadMesh,"building artwork is a flat sprite")
	if node is MultiMeshInstance3D: check(node.multimesh.mesh is BoxMesh,"facade details have depth")
	for child in node.get_children(): inspect(child)
func run() -> void:
	Map.lots.assign([Rect2(-90,-90,180,180)]); Map.lot_angles.assign([.4]); Map.lot_districts.assign(["RESIDENTIAL"])
	Map.building_data.assign([{"asset_variant":1,"height_m":15,"style":"perimeter"}]); Map.interior_data={}
	for kind in ["apartment","house","fire","police","medical"]:
		Map.pois.clear(); Map.lot_districts[0]="GROVE" if kind=="house" else "RESIDENTIAL"
		if kind in ["fire","police","medical"]:
			Map.pois.append({"footprint":Map.lots[0],"kind":{"fire":"Fire Station","police":"Police Station","medical":"Medical Station"}[kind]})
		var building:=Building.new(); building.configure(Map.lots[0],0); root.add_child(building)
		check(building.has_node("BuildingSprite"),"sprite shell "+kind)
		check(building.get_meta("architecture_type")==kind,"correct architecture "+kind)
		check(is_equal_approx(building.rotation.y,.4),"building respects parcel orientation")
		inspect(building.get_node("BuildingSprite"))
		var recipe=preload("res://scripts/three_d/building_shape.gd").plan(0)
		check(building.get_children().filter(func(n):return n is StaticBody3D).size()==recipe.wings.size(),"collision matches structural wings")
		if kind=="medical": check(building.height>=22,"medical tower proportions")
		if kind=="fire": check(recipe.wings.size()==2 and recipe.wings[1][0].y>recipe.wings[0][0].y,"fire tower silhouette and collider recipe")
		building.free()
	print("Building sprites: %d checks / %d failures"%[checks,failures]); quit(1 if failures else 0)
