extends RefCounted
## Small primitive factory, shared by buildings, shelters and environmental markers.

static func material(color: Color, unshaded: bool = false) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = 0.88
	if unshaded:
		result.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return result

static func box(parent: Node3D, size: Vector3, position: Vector3, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.material_override = material(color)
	node.position = position
	parent.add_child(node)
	return node

static func cylinder(parent: Node3D, radius: float, height: float, position: Vector3, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 16
	node.mesh = mesh
	node.material_override = material(color)
	node.position = position
	parent.add_child(node)
	return node

static func label(parent: Node3D, text: String, position: Vector3, color: Color, font_size: int = 40, pixel_size: float = 0.035) -> Label3D:
	var node := Label3D.new()
	node.text = text
	node.position = position
	node.modulate = color
	node.font_size = font_size
	node.pixel_size = pixel_size
	node.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	node.outline_size = 8
	node.no_depth_test = false
	parent.add_child(node)
	return node

static func collider(parent: Node3D, size: Vector3, position: Vector3, layer: int = 1) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = position
	body.collision_layer = layer
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)
	parent.add_child(body)
	return body

static func ring(parent: Node3D, radius: float, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = radius - 0.07
	mesh.outer_radius = radius + 0.07
	mesh.rings = 24
	mesh.ring_segments = 6
	node.mesh = mesh
	node.material_override = material(color, true)
	parent.add_child(node)
	return node
