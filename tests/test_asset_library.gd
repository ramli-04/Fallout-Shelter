extends SceneTree

const Browser = preload("res://scripts/asset_library_browser.gd")
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/ASSET_MANIFEST.json"))
	_check(parsed is Dictionary, "asset manifest parses")
	var models := 0
	for item in parsed.assets:
		if str(item.get("format", "")) != "glb":
			continue
		models += 1
		var packed := ResourceLoader.load(str(item.get("path", ""))) as PackedScene
		_check(packed != null, "Godot imports %s" % item.get("path", ""))
	_check(models == 11, "all selected, license-cleared model GLBs are registered")
	var held_animation := false
	for item in parsed.get("held_assets", []):
		if item.get("id", "") == "QANIM01" and item.get("license_status", "") == "LICENSE_CONFLICT_HOLD" and not item.has("path"):
			held_animation = true
	_check(held_animation, "conflicting Quaternius package remains held outside the imported library")
	var browser := Browser.new()
	root.add_child(browser)
	browser.popup_centered(Vector2i(1180, 760))
	await process_frame
	_check(browser.display_assets.size() == 11, "developer browser lists all license-cleared preview models")
	await create_timer(0.35).timeout
	_capture_preview(browser, "asset_library_sedan_preview.png")
	var building_index := _asset_index(browser, "KBC01")
	_check(building_index >= 0, "commercial building model is available")
	if building_index >= 0:
		browser._on_asset_selected(building_index)
		await create_timer(0.25).timeout
		_capture_preview(browser, "asset_library_building_preview.png")
	var emergency_index := _asset_index(browser, "KEM02")
	_check(emergency_index >= 0, "emergency vehicle model is available")
	if emergency_index >= 0:
		browser._on_asset_selected(emergency_index)
		await create_timer(0.25).timeout
		_capture_preview(browser, "asset_library_ambulance_preview.png")
	browser.queue_free()
	_finish()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("Asset library test failed: " + message)


func _finish() -> void:
	if failures.is_empty():
		print("ASSET_LIBRARY_TESTS_PASSED")
		quit(0)
	else:
		print("ASSET_LIBRARY_TESTS_FAILED: %s" % " | ".join(failures))
		quit(1)


func _capture_preview(browser: Browser, filename: String) -> void:
	if browser.preview_viewport.get_texture() == null:
		print("PREVIEW_CAPTURE_SKIPPED / renderer has no readable viewport texture")
		return
	var image: Image = browser.preview_viewport.get_texture().get_image()
	if image == null or image.is_empty():
		print("PREVIEW_CAPTURE_SKIPPED / renderer did not provide a readback image")
		return
	var output_dir := OS.get_cache_dir().path_join("ESSAIM_asset_library_previews")
	DirAccess.make_dir_recursive_absolute(output_dir)
	var status: Error = image.save_png(output_dir.path_join(filename))
	_check(status == OK, "preview screenshot saved: " + filename)
	if status == OK:
		print("PREVIEW_CAPTURED / ", output_dir.path_join(filename))


func _asset_index(browser: Browser, wanted_id: String) -> int:
	for index in range(browser.display_assets.size()):
		if browser.display_assets[index].get("id", "") == wanted_id:
			return index
	return -1
