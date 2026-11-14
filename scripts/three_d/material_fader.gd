extends RefCounted
## One reversible material effect, shared by buildings and vault structures.
var owner: WeakRef
var settings: Dictionary
var records: Array=[]
var amount:=1.0
var obscured:=false
var tween: Tween
func configure(root: Node3D,options: Dictionary) -> void: owner=weakref(root); settings=options
func set_obscured(value: bool) -> void:
	if value==obscured: return
	obscured=value
	if is_instance_valid(tween): tween.kill()
	if records.is_empty(): _collect(owner.get_ref())
	tween=owner.get_ref().create_tween()
	tween.tween_method(_apply,amount,float(settings.occlusion_alpha) if value else 1.0,float(settings.fade_seconds))
	if not value: tween.tween_callback(_restore)
func _collect(node: Node) -> void:
	for child in node.get_children():
		if child is GeometryInstance3D and child.material_override is ShaderMaterial and child.material_override.get_shader_parameter("opacity")!=null:
			var original: ShaderMaterial=child.material_override; var faded: ShaderMaterial=original.duplicate()
			child.material_override=faded; records.append({"node":child,"original":original,"faded":faded,"surface":-1,"shader":true})
		elif child is GeometryInstance3D and child.material_override is StandardMaterial3D:
			var original: StandardMaterial3D=child.material_override; var faded: StandardMaterial3D=original.duplicate()
			child.material_override=faded; records.append({"node":child,"original":original,"faded":faded,"surface":-1})
		elif child is MeshInstance3D and child.mesh!=null and child.material_override==null:
			for index in range(child.mesh.get_surface_count()):
				var overridden: Material=child.get_surface_override_material(index)
				var original: Material=overridden if overridden!=null else child.mesh.surface_get_material(index)
				if original is StandardMaterial3D:
					var faded: StandardMaterial3D=original.duplicate(); child.set_surface_override_material(index,faded)
					records.append({"node":child,"original":original,"faded":faded,"surface":index,"override":overridden})
		_collect(child)
func _apply(value: float) -> void:
	amount=value
	for entry in records:
		if entry.get("shader",false):
			entry.faded.set_shader_parameter("opacity",value)
			# Camera-facing sprite texture can change while its fade copy is active.
			var artwork: Variant=entry.original.get_shader_parameter("artwork")
			if artwork is Texture2D: entry.faded.set_shader_parameter("artwork",artwork)
			continue
		entry.faded.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
		var color: Color=entry.original.albedo_color; color.a*=value; entry.faded.albedo_color=color
func _restore() -> void:
	for entry in records:
		if is_instance_valid(entry.node):
			if entry.surface<0: entry.node.material_override=entry.original
			else: entry.node.set_surface_override_material(entry.surface,entry.override)
	records.clear(); amount=1.0
func reset() -> void:
	if is_instance_valid(tween): tween.kill()
	obscured=false; _restore()
