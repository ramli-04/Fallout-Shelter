class_name WorldGenerationManager
extends Node
## Worker produces immutable JSON only. Live Map/scene changes happen at handoff.
signal completed(success: bool)
signal status_changed(message: String)
signal progress_changed(percent: int,stage: String)
var progress_file:=""
var last_progress:=-1
const Map=preload("res://scripts/city_map.gd")
const FORMAT_VERSION:=1
const GENERATOR_VERSION:="essaim-world-4"
var current: Dictionary={}
var current_json:=""
var busy:=false
var status:="Historical map; generate a procedural world before starting."
var error:=""
var worker:=Thread.new()
var last_request: Dictionary={}
var generation_count:=0

static func random_seed() -> int:
	# Entropy is used only to choose a displayed seed, never inside the pipeline.
	var bytes:=Crypto.new().generate_random_bytes(4)
	return int(bytes.decode_u32(0)%2147483647)

func _ready() -> void: name="WorldGenerationManager"

func generate(seed_value: int, options: Dictionary = {}) -> bool:
	return _begin({"world_seed":seed_value,"preset":options.get("preset","medium"),
		"district_density":options.get("district_density",1.0),
		"vegetation_density":options.get("vegetation_density",1.0),
		"road_width_multiplier":options.get("road_width_multiplier",1.0),
		"straight_road_ratio":options.get("straight_road_ratio",0.7)})

func load_world(path: String) -> bool:
	return _begin({"load_path":ProjectSettings.globalize_path(path)})

func _begin(request: Dictionary) -> bool:
	if busy: return false
	busy=true; error=""; last_request=request.duplicate(true)
	status="Generating / validating on background worker…"; status_changed.emit(status)
	var root_path:=ProjectSettings.globalize_path("res://")
	var cache:=ProjectSettings.globalize_path("user://worlds/cache")
	DirAccess.make_dir_recursive_absolute(cache)
	progress_file=cache.path_join("progress_%d_%d.json"%[OS.get_process_id(),Time.get_ticks_usec()])
	request["progress_path"]=progress_file; last_progress=-1
	progress_changed.emit(0,"Starting generation")
	var result:=worker.start(_produce.bind(request.duplicate(true),root_path,cache))
	if result!=OK:
		busy=false; error=error_string(result); status=error; status_changed.emit(status); return false
	return true

static func _produce(request: Dictionary, root_path: String, cache: String) -> Dictionary:
	var key:=JSON.stringify(request,"",true,true).sha256_text()
	var input:=cache.path_join("request_%d_%s.json"%[OS.get_process_id(),key])
	var output:=cache.path_join("world_%s.json"%key)
	var file:=FileAccess.open(input,FileAccess.WRITE)
	if file==null: return {"error":"Cannot write generation request"}
	file.store_string(JSON.stringify(request)); file.close()
	var python:=root_path.path_join(".venv/Scripts/python.exe")
	if not FileAccess.file_exists(python): python="python3"
	var logs:=[]
	var code:=OS.execute(python,["-m","ai_service.world_generation",input,output],logs,true)
	if code!=0: return {"error":"World generation rejected: "+str(logs)}
	var source:=FileAccess.get_file_as_string(output)
	var data: Variant=JSON.parse_string(source)
	if not data is Dictionary: return {"error":"Invalid world JSON"}
	return {"data":data,"json":source}

func _process(_delta: float) -> void:
	if busy and FileAccess.file_exists(progress_file):
		var progress: Variant=JSON.parse_string(FileAccess.get_file_as_string(progress_file))
		if progress is Dictionary and int(progress.get("percent",0))!=last_progress:
			last_progress=int(progress.percent); progress_changed.emit(last_progress,str(progress.get("stage","Generating")))
	if not busy or worker.is_alive(): return
	var result: Dictionary=worker.wait_to_finish()
	busy=false
	if result.has("error"):
		error=result.error; status=error; status_changed.emit(status); completed.emit(false); return
	progress_changed.emit(100,"Map validated")
	current=result.data; current_json=result.json; generation_count+=1
	status="Validated %s / %s / attempt %d"%[current.world_id,current.layout_pattern,int(current.attempt)+1]
	status_changed.emit(status); completed.emit(true)

func apply(options: Dictionary = {}) -> bool:
	if busy or current.is_empty(): return false
	if int(current.get("format_version",0))!=FORMAT_VERSION or current.get("generator_version","") not in ["essaim-world-1","essaim-world-2","essaim-world-3",GENERATOR_VERSION]:
		error="Unsupported world version"; return false
	var runtime_options:=options.duplicate(true); runtime_options.merge(current.settings,true)
	if not Map.load_layout(current.layout,runtime_options): error=Map.generation_error; return false
	Map.generated_world=metadata()
	return true

func save_world(path: String) -> bool:
	if busy or current.is_empty() or current_json.is_empty(): error="No generated world to save"; return false
	var target:=ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(target.get_base_dir())
	var temporary:=target+".tmp"
	var file:=FileAccess.open(temporary,FileAccess.WRITE)
	if file==null: error="Cannot write world configuration"; return false
	# Preserve canonical numeric bytes across Godot/Python JSON implementations.
	file.store_string(current_json); file.close()
	var result:=DirAccess.rename_absolute(temporary,target)
	if result!=OK: error=error_string(result)
	return result==OK

func metadata() -> Dictionary:
	if current.is_empty(): return {"world_seed":Map.map_seed,"generator_version":"historical-city-%d"%Map.layout_version}
	return {"world_seed":current.world_seed,"world_id":current.world_id,
		"world_format_version":current.format_version,"generator_version":current.generator_version,
		"world_content_hash":current.content_hash}

func _exit_tree() -> void:
	if worker.is_started(): worker.wait_to_finish()
