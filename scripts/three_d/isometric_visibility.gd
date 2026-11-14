extends RefCounted
## Orthographic sightlines remain parallel, including away from screen center.
static func sightline(camera: Camera3D, target: Vector3) -> PhysicsRayQueryParameters3D:
	var pixel := camera.unproject_position(target)
	return PhysicsRayQueryParameters3D.create(camera.project_ray_origin(pixel),target,1)

static func obscured_buildings(camera: Camera3D, space: PhysicsDirectSpaceState3D, agents: Array, buildings: Array, max_layers: int = 12) -> Array:
	var obscured: Array = []
	var screen := camera.get_viewport().get_visible_rect()
	var by_index: Dictionary={}
	for building in buildings:
		if building.has_meta("building_index"): by_index[building.get_meta("building_index")]=building
	for agent in agents:
		if not agent.is_visible_in_tree(): continue
		var target: Vector3 = agent.global_position+Vector3.UP
		if camera.is_position_behind(target) or not screen.has_point(camera.unproject_position(target)): continue
		var query := sightline(camera,target)
		# Several walls/buildings may overlap one survivor. Bound work per agent.
		for layer in range(clampi(max_layers,1,64)):
			var hit := space.intersect_ray(query)
			if hit.is_empty(): break
			var owner: Node = hit.collider
			if owner.has_meta("building_index"):
				owner=by_index.get(owner.get_meta("building_index"))
			while owner != null and owner not in buildings: owner = owner.get_parent()
			if owner != null and owner not in obscured: obscured.append(owner)
			var excluded := query.exclude
			excluded.append(hit.rid)
			query.exclude = excluded
	return obscured
