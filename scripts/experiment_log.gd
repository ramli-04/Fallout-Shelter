extends RefCounted
## Immutable run snapshots are serialized/written off the scene thread.
static func enqueue(snapshot: Dictionary, workers: Array[Thread]) -> String:
	var path := "res://outputs/experiment_runs/seed_%d_%d_%d.json" % [snapshot["seed"],int(Time.get_unix_time_from_system()),Time.get_ticks_usec()]
	var worker := Thread.new()
	var error := worker.start(write_file.bind(path,snapshot.duplicate(true)))
	if error != OK:
		push_error("Cannot start experiment archive worker: " + error_string(error))
		return ""
	workers.append(worker)
	return path
static func write_file(path: String, snapshot: Dictionary) -> int:
	var error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://outputs/experiment_runs"))
	if error != OK: return error
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_string(JSON.stringify(json_value(snapshot)))
	file.close()
	return OK
static func json_value(value: Variant) -> Variant:
	if value is Vector2: return [value.x,value.y]
	if value is Rect2: return {"position": json_value(value.position),"size": json_value(value.size)}
	if value is Dictionary:
		var result := {}
		for key in value: result[key] = json_value(value[key])
		return result
	if value is Array or value is PackedVector2Array:
		var result := []
		for item in value: result.append(json_value(item))
		return result
	return value
