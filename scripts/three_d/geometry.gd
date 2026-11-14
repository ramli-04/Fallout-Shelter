extends RefCounted
## Small primitive factory, shared by buildings, shelters and environmental markers.

static var box_meshes: Dictionary = {}
static var cylinder_meshes: Dictionary = {}
static var capsule_meshes: Dictionary = {}
static var sphere_meshes: Dictionary = {}
static var ring_meshes: Dictionary = {}
static var materials: Dictionary = {}
static var world_cache_key:=""
static func begin_world(key: String) -> void:
	if key==world_cache_key: return
	# Live nodes retain their resources; only the factory's old lookup is released.
	box_meshes.clear(); cylinder_meshes.clear(); capsule_meshes.clear(); sphere_meshes.clear(); ring_meshes.clear(); materials.clear(); world_cache_key=key

static func material(color: Color, unshaded: bool = false) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = 0.88
	if unshaded:
		result.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return result

## Immutable material shared by generated geometry. Use material() for a node that changes at runtime.
static func shared_material(color: Color, unshaded: bool = false) -> StandardMaterial3D:
	var key: String = color.to_html(true) + ("|unshaded" if unshaded else "|lit")
	if not materials.has(key): materials[key] = material(color,unshaded)
	return materials[key]

static func make_mesh_unique(node: MeshInstance3D) -> void:
	if node.mesh != null: node.mesh = node.mesh.duplicate()
	make_material_unique(node)

static func make_material_unique(node: MeshInstance3D) -> void:
	if node.material_override != null: node.material_override = node.material_override.duplicate()

static func box(parent: Node3D, size: Vector3, position: Vector3, color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	if not box_meshes.has(size):
		var created := BoxMesh.new()
		created.size = size
		box_meshes[size] = created
	var mesh: BoxMesh = box_meshes[size]
	node.mesh = mesh
	node.material_override = shared_material(color)
	node.position = position
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node

static func cylinder_mesh(radius: float, height: float, radial_segments: int = 16) -> CylinderMesh:
	var key: String = "%.4f|%.4f|%d" % [radius,height,radial_segments]
	if not cylinder_meshes.has(key):
		var created := CylinderMesh.new()
		created.top_radius = radius
		created.bottom_radius = radius
		created.height = height
		created.radial_segments = radial_segments
		cylinder_meshes[key] = created
	return cylinder_meshes[key]

static func cylinder(parent: Node3D, radius: float, height: float, position: Vector3, color: Color, radial_segments: int = 16) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = cylinder_mesh(radius,height,radial_segments)
	node.material_override = shared_material(color)
	node.position = position
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node

static func capsule_mesh(radius: float, height: float, radial_segments: int = 10, rings: int = 3) -> CapsuleMesh:
	var key: String = "%.4f|%.4f|%d|%d" % [radius,height,radial_segments,rings]
	if not capsule_meshes.has(key):
		var created := CapsuleMesh.new()
		created.radius = radius
		created.height = maxf(height,radius*2.0)
		created.radial_segments = radial_segments
		created.rings = rings
		capsule_meshes[key] = created
	return capsule_meshes[key]

static func capsule(parent: Node3D, radius: float, height: float, position: Vector3, color: Color, radial_segments: int = 10, rings: int = 3) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = capsule_mesh(radius,height,radial_segments,rings)
	node.material_override = shared_material(color)
	node.position = position
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node

static func sphere(parent: Node3D, radius: float, height: float, position: Vector3, color: Color, radial_segments: int = 12, rings: int = 6) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var key: String = "%.4f|%.4f|%d|%d" % [radius,height,radial_segments,rings]
	if not sphere_meshes.has(key):
		var created := SphereMesh.new()
		created.radius = radius
		created.height = height
		created.radial_segments = radial_segments
		created.rings = rings
		sphere_meshes[key] = created
	node.mesh = sphere_meshes[key]
	node.material_override = shared_material(color)
	node.position = position
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
	var key: String = "%.4f" % radius
	if not ring_meshes.has(key):
		var created := TorusMesh.new()
		created.inner_radius = radius - 0.07
		created.outer_radius = radius + 0.07
		created.rings = 24
		created.ring_segments = 6
		ring_meshes[key] = created
	var mesh: TorusMesh = ring_meshes[key]
	node.mesh = mesh
	node.material_override = shared_material(color, true)
	parent.add_child(node)
	return node
