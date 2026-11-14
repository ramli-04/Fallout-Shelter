extends Window
## Development-only browser for locally imported assets. It never downloads files.

const Dashboard = preload("res://scripts/dashboard.gd")
const MANIFEST_PATH := "res://assets/ASSET_MANIFEST.json"

var manifest_assets: Array[Dictionary] = []
var display_assets: Array[Dictionary] = []
var category_filter := "All"
var search_text := ""
var asset_list: ItemList
var category_picker: OptionButton
var search_field: LineEdit
var details_label: RichTextLabel
var preview_root: Node3D
var preview_viewport: SubViewport
var animation_picker: OptionButton
var animation_status: Label
var active_animation_player: AnimationPlayer
var active_animation_names: Array[String] = []
var selected_id := ""


func _ready() -> void:
	title = "ESSAIM / ASSET LIBRARY"
	size = Vector2i(1180, 760)
	min_size = Vector2i(900, 620)
	theme = Dashboard.light_theme()
	close_requested.connect(hide)
	visibility_changed.connect(_sync_preview_rendering)
	_build_ui()
	_read_manifest()
	_sync_preview_rendering()


func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	var heading := HBoxContainer.new()
	column.add_child(heading)
	var title_label := Label.new()
	title_label.text = "ASSET LIBRARY  /  RUNTIME MODELS AND LOCAL PREVIEWS"
	title_label.add_theme_font_size_override("font_size", 17)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title_label)
	var note := Label.new()
	note.text = "No launch-time downloads"
	note.add_theme_color_override("font_color", Dashboard.MUTED)
	heading.add_child(note)
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.split_offset = 270
	column.add_child(split)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(250, 0)
	left.add_theme_constant_override("separation", 8)
	split.add_child(left)
	var filter_row := HBoxContainer.new()
	left.add_child(filter_row)
	category_picker = OptionButton.new()
	category_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for category in ["All", "Vehicles", "Buildings", "Character animation"]:
		category_picker.add_item(category)
	filter_row.add_child(category_picker)
	category_picker.item_selected.connect(func(index: int):
		category_filter = category_picker.get_item_text(index)
		_refresh_asset_list()
	)
	search_field = LineEdit.new()
	search_field.placeholder_text = "Search assets"
	left.add_child(search_field)
	search_field.text_changed.connect(func(value: String):
		search_text = value.strip_edges().to_lower()
		_refresh_asset_list()
	)
	asset_list = ItemList.new()
	asset_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	asset_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	asset_list.item_selected.connect(_on_asset_selected)
	left.add_child(asset_list)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	split.add_child(right)
	var preview_panel := PanelContainer.new()
	preview_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_panel.custom_minimum_size = Vector2(600, 380)
	right.add_child(preview_panel)
	var preview_stack := VBoxContainer.new()
	preview_panel.add_child(preview_stack)
	var viewport_container := SubViewportContainer.new()
	viewport_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	viewport_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	viewport_container.stretch = true
	preview_stack.add_child(viewport_container)
	preview_viewport = SubViewport.new()
	preview_viewport.size = Vector2i(800, 480)
	preview_viewport.own_world_3d = true
	preview_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport_container.add_child(preview_viewport)
	var world := Node3D.new()
	world.name = "PreviewWorld"
	preview_viewport.add_child(world)
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("bdc9c6")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("dce3da")
	environment.ambient_light_energy = 0.8
	environment_node.environment = environment
	world.add_child(environment_node)
	var floor := MeshInstance3D.new()
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(12, 12)
	floor.mesh = floor_mesh
	floor.position.y = -0.04
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color("84918b")
	floor_material.roughness = 0.95
	floor.material_override = floor_material
	world.add_child(floor)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 4.2
	var view_target := Vector3(0, 0.85, 0)
	var view_distance := 5.1
	var camera_settings: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://resources/visual_3d.json")).get("camera", {})
	var yaw := deg_to_rad(float(camera_settings.get("isometric_yaw_degrees", 45.0)))
	var pitch := deg_to_rad(float(camera_settings.get("isometric_pitch_degrees", 35.264)))
	var horizontal_distance := view_distance * cos(pitch)
	camera.position = view_target + Vector3(sin(yaw) * horizontal_distance, sin(pitch) * view_distance, cos(yaw) * horizontal_distance)
	camera.current = true
	world.add_child(camera)
	camera.look_at(view_target, Vector3.UP)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-43, -32, 0)
	light.light_energy = 1.4
	world.add_child(light)
	preview_root = Node3D.new()
	preview_root.name = "AssetPreview"
	world.add_child(preview_root)
	var animation_row := HBoxContainer.new()
	animation_row.add_theme_constant_override("separation", 8)
	preview_stack.add_child(animation_row)
	animation_status = Label.new()
	animation_status.text = "Select a model to preview"
	animation_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	animation_row.add_child(animation_status)
	animation_picker = OptionButton.new()
	animation_picker.custom_minimum_size = Vector2(230, 0)
	animation_picker.disabled = true
	animation_row.add_child(animation_picker)
	animation_picker.item_selected.connect(_play_selected_animation)
	details_label = RichTextLabel.new()
	details_label.bbcode_enabled = true
	details_label.fit_content = true
	details_label.scroll_active = true
	details_label.custom_minimum_size = Vector2(0, 125)
	details_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(details_label)


func _read_manifest() -> void:
	if not FileAccess.file_exists(MANIFEST_PATH):
		animation_status.text = "Asset manifest missing: " + MANIFEST_PATH
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	if not parsed is Dictionary or not (parsed.get("assets", []) is Array):
		animation_status.text = "Asset manifest could not be parsed."
		return
	for item in parsed.assets:
		if item is Dictionary and str(item.get("path", "")).get_extension().to_lower() in ["glb", "gltf"]:
			manifest_assets.append(item)
	_refresh_asset_list()


func _refresh_asset_list() -> void:
	if asset_list == null:
		return
	asset_list.clear()
	display_assets.clear()
	selected_id = ""
	for item in manifest_assets:
		var category := str(item.get("category", ""))
		if category_filter == "Vehicles" and not category.begins_with("vehicle_"):
			continue
		if category_filter == "Buildings" and not category.begins_with("building_"):
			continue
		if category_filter == "Character animation" and category != "character_animation":
			continue
		if not search_text.is_empty() and search_text not in str(item.get("name", "")).to_lower():
			continue
		display_assets.append(item)
		var name := str(item.get("name", "Unnamed"))
		var triangles := int(item.get("polygon_count", 0))
		asset_list.add_item("%s  ·  %s tris" % [name, _format_number(triangles)])
		asset_list.set_item_metadata(asset_list.get_item_count() - 1, str(item.get("id", "")))
	if not display_assets.is_empty():
		asset_list.select(0)
		_on_asset_selected(0)
	else:
		_clear_preview("No assets match this filter.")


func _on_asset_selected(index: int) -> void:
	if index < 0 or index >= display_assets.size():
		return
	var item: Dictionary = display_assets[index]
	selected_id = str(item.get("id", ""))
	_load_preview(item)
	_update_details(item)


func _load_preview(item: Dictionary) -> void:
	for child in preview_root.get_children():
		child.queue_free()
	active_animation_player = null
	active_animation_names.clear()
	animation_picker.clear()
	animation_picker.disabled = true
	var resource_path := str(item.get("path", ""))
	var packed := load(resource_path) as PackedScene
	if packed == null:
		_clear_preview("Godot could not load " + resource_path)
		return
	var instance := packed.instantiate()
	preview_root.add_child(instance)
	instance.position = Vector3.ZERO
	var scale_factor := float(item.get("preview_scale", 1.0))
	instance.scale = Vector3.ONE * scale_factor
	active_animation_player = _find_animation_player(instance)
	if active_animation_player == null:
		animation_status.text = "Static preview · %s" % str(item.get("godot_import_status", "import status pending"))
		return
	for animation_name in active_animation_player.get_animation_list():
		active_animation_names.append(animation_name)
	for animation_name in active_animation_names:
		animation_picker.add_item(animation_name)
	animation_picker.disabled = active_animation_names.is_empty()
	if active_animation_names.is_empty():
		animation_status.text = "Rigged model · no clips imported"
	else:
		animation_status.text = "Animation preview · %d clips · no root motion" % active_animation_names.size()
		var default_animation := 0
		for animation_index in range(active_animation_names.size()):
			if active_animation_names[animation_index].to_lower().contains("walk"):
				default_animation = animation_index
				break
		active_animation_player.play(active_animation_names[default_animation])
		animation_picker.select(default_animation)


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null


func _play_selected_animation(index: int) -> void:
	if active_animation_player == null or index < 0 or index >= active_animation_names.size():
		return
	active_animation_player.play(active_animation_names[index])


func _update_details(item: Dictionary) -> void:
	var texture_lines := PackedStringArray()
	for texture in item.get("textures", []):
		texture_lines.append("%s×%s" % [texture.get("width", "?"), texture.get("height", "?")])
	var texture_summary := ", ".join(texture_lines) if not texture_lines.is_empty() else "none / embedded"
	var duplicates: Array = item.get("duplicate_of", [])
	var duplicate_summary := ", ".join(duplicates) if not duplicates.is_empty() else "no exact file duplicate"
	var usage := str(item.get("usage_status", "NOT_SCANNED"))
	var source_references := int(item.get("source_references", 0))
	var lines := [
		"[b]%s[/b]  ·  %s" % [str(item.get("name", "Unnamed")), str(item.get("category", ""))],
		"Source: %s · Creator: %s · License: %s" % [str(item.get("original_source", "")), str(item.get("author", "")), str(item.get("license", "Unknown"))],
		"Attribution required: %s · Commercial use: %s · Format: %s · File: %s" % [str(item.get("attribution_required", "unknown")), str(item.get("commercial_use", "unknown")), str(item.get("format", "unknown")), _format_bytes(int(item.get("file_size_bytes", 0)))],
		"Geometry: %s triangles · %s meshes · %s materials · %s bones · %s animation clips" % [_format_number(int(item.get("polygon_count", 0))), str(item.get("mesh_count", 0)), str(item.get("material_count", 0)), str(item.get("bone_count", 0)), str(item.get("animation_count", 0))],
		"Textures: %s · estimated RGBA+mips: %s" % [texture_summary, _format_bytes(int(item.get("estimated_texture_vram_bytes", 0)))],
		"Godot import: %s" % str(item.get("godot_import_status", "pending")),
		"Duplicate check: %s · Direct source references: %d · Usage: %s · Optimization: %s" % [duplicate_summary, source_references, usage, str(item.get("optimization_status", "not reviewed"))],
		"Runtime binding: %s" % str(item.get("runtime_integration", "not configured")),
		"Publisher page: %s" % str(item.get("download_page", "")),
		"Notes: %s" % str(item.get("notes", "")),
	]
	details_label.text = "\n".join(lines)


func _clear_preview(message: String) -> void:
	if animation_status != null:
		animation_status.text = message
	if details_label != null and selected_id.is_empty():
		details_label.text = message


func _sync_preview_rendering() -> void:
	if preview_viewport == null:
		return
	preview_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if visible else SubViewport.UPDATE_DISABLED


func _format_number(value: int) -> String:
	var raw := str(value)
	var result := ""
	while raw.length() > 3:
		result = "," + raw.substr(raw.length() - 3, 3) + result
		raw = raw.substr(0, raw.length() - 3)
	return raw + result


func _format_bytes(value: int) -> String:
	if value >= 1024 * 1024:
		return "%.1f MiB" % (float(value) / (1024.0 * 1024.0))
	if value >= 1024:
		return "%.1f KiB" % (float(value) / 1024.0)
	return "%d B" % value
