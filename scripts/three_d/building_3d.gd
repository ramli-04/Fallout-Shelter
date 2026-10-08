extends Node3D
## Reusable static obstruction; color/height are deterministic visual choices, not RNG draws.
const Geometry = preload("res://scripts/three_d/geometry.gd")
var footprint := Rect2()
var height := 0.0

func configure(rect: Rect2, index: int) -> void:
	footprint = rect
	var scale_value := preload("res://scripts/three_d/world_coordinates.gd").SCALE
	var center: Vector2 = rect.get_center() * scale_value
	position = Vector3(center.x, 0.18, center.y)
	var district := int(center.x / 60)
	var palettes := [Color("d99c77"), Color("a5c3c3"), Color("839aaa")]
	var color: Color = palettes[mini(district, 2)].lightened((index%3)*0.055)
	height = 3.0 + (index%4)*1.35 if district == 0 else 4.2 + (index%5)*1.6 if district == 1 else 5.0 + (index%4)*2.1
	var size := Vector3(rect.size.x*scale_value, height, rect.size.y*scale_value)
	Geometry.box(self, size, Vector3(0, height/2, 0), color)
	Geometry.box(self, Vector3(size.x+0.3, 0.22, size.z+0.3), Vector3(0, height+0.08, 0), Color("465b63"))
	Geometry.box(self, Vector3(size.x+0.2, 0.25, size.z+0.2), Vector3(0, 0.12, 0), Color("718784"))
	Geometry.collider(self, size, Vector3(0, height/2, 0))
	# One instanced draw per building for all repeated facade windows.
	var windows := MultiMeshInstance3D.new()
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.25, 0.8, 0.06)
	multimesh.mesh = mesh
	var floors := maxi(1, int(height/2))
	multimesh.instance_count = floors*12
	var window_index := 0
	for floor_index in range(floors):
		for side in range(4):
			for offset in [-2.8, 0.0, 2.8]:
				var basis := Basis(Vector3.UP, side*PI/2)
				var point := basis * Vector3(offset, 1.1 + floor_index*1.8, size.z/2+0.04)
				multimesh.set_instance_transform(window_index, Transform3D(basis, point))
				window_index += 1
	windows.multimesh = multimesh
	windows.material_override = Geometry.material(Color("e1edda"))
	add_child(windows)
