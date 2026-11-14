extends RefCounted
## Central map for the license-checked Kenney models used by the live renderer.
const BUILDINGS := [
	"res://assets/buildings/commercial/kenney/building-a.glb",
	"res://assets/buildings/commercial/kenney/building-b.glb",
	"res://assets/buildings/commercial/kenney/building-c.glb",
]
const BUILDINGS_LOD := [
	"res://assets/buildings/commercial/kenney/low-detail-building-a.glb",
	"res://assets/buildings/commercial/kenney/low-detail-building-b.glb",
	"res://assets/buildings/commercial/kenney/low-detail-building-c.glb",
]
const VEHICLES := {
	"sedan": "res://assets/vehicles/civilian/kenney/sedan.glb",
	"suv": "res://assets/vehicles/civilian/kenney/suv.glb",
	"police": "res://assets/vehicles/emergency/kenney/police.glb",
	"ambulance": "res://assets/vehicles/emergency/kenney/ambulance.glb",
	"firetruck": "res://assets/vehicles/emergency/kenney/firetruck.glb",
}

static func building_path(index: int, low_detail: bool = false) -> String:
	var data: Dictionary = preload("res://scripts/city_map.gd").building_data[index]
	var variant := posmod(int(data.get("asset_variant", index)), 3)
	return BUILDINGS_LOD[variant] if low_detail else BUILDINGS[variant]

static func vehicle_path(model: String, kind: String) -> String:
	if model == "swat": return VEHICLES.suv
	if kind == "Police": return VEHICLES.police
	if kind == "Medical": return VEHICLES.ambulance
	if kind == "Fire": return VEHICLES.firetruck
	if kind == "Civil protection": return VEHICLES.suv
	return VEHICLES.suv if model in ["suv", "pickup", "van", "delivery_truck", "minibus"] else VEHICLES.sedan

static func local_bounds(root: Node) -> AABB:
	var state := {"found": false, "bounds": AABB()}
	_accumulate_bounds(root, Transform3D.IDENTITY, state)
	return state.bounds

static func _accumulate_bounds(node: Node, parent_transform: Transform3D, state: Dictionary) -> void:
	var transform := parent_transform
	if node is Node3D:
		transform = parent_transform * (node as Node3D).transform
	if node is VisualInstance3D:
		var local_box: AABB = (node as VisualInstance3D).get_aabb()
		for x in [0.0, 1.0]:
			for y in [0.0, 1.0]:
				for z in [0.0, 1.0]:
					var corner := local_box.position + local_box.size * Vector3(x, y, z)
					var point := transform * corner
					if state.found:
						state.bounds = state.bounds.expand(point)
					else:
						state.bounds = AABB(point, Vector3.ZERO)
						state.found = true
	for child in node.get_children():
		_accumulate_bounds(child, transform, state)

static func first_mesh(root: Node) -> MeshInstance3D:
	if root is MeshInstance3D:
		return root
	for child in root.get_children():
		var found := first_mesh(child)
		if found != null:
			return found
	return null
