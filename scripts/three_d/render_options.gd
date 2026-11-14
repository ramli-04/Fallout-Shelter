extends RefCounted
## One normalized configuration keeps geometry partitions and residency aligned.
const PATH:="res://resources/render_streaming.json"
const DEFAULTS:={"enabled":true,"chunk_size":1200,"preload_distance":360,"unload_distance":720,"update_interval":.15,"frame_budget_ms":4.0,"buildings_per_frame":2,"pooled_chunks":2,"pooled_agents":24,"detail_view_size":420,"facade_view_size":150,"detail_distance":220,"animation_full_distance":42,"animation_medium_distance":125,"animation_medium_interval":.10,"animation_far_interval":.30,"occlusion_interval":.12,"occlusion_alpha":.18,"fade_seconds":.25,"restore_delay":.22,"max_occlusion_layers":12,"show_metrics":false}
static var cached: Dictionary={}
static func normalize(values: Dictionary) -> Dictionary:
	var result:=DEFAULTS.duplicate(true); result.merge(values,true)
	for key in DEFAULTS:
		if DEFAULTS[key] is bool:
			if not result[key] is bool: result[key]=DEFAULTS[key]
		elif not (result[key] is float or result[key] is int) or not is_finite(float(result[key])): result[key]=DEFAULTS[key]
	result.chunk_size=clampf(roundf(float(result.chunk_size)/120)*120,600,2400)
	result.preload_distance=clampf(float(result.preload_distance),0,2400)
	result.unload_distance=clampf(float(result.unload_distance),float(result.preload_distance)+120,3600)
	for key in ["update_interval","occlusion_interval"]: result[key]=clampf(float(result[key]),.05,1.0)
	result.frame_budget_ms=clampf(float(result.frame_budget_ms),1,16)
	result.buildings_per_frame=clampi(int(result.buildings_per_frame),1,8)
	result.pooled_chunks=clampi(int(result.pooled_chunks),0,8); result.pooled_agents=clampi(int(result.pooled_agents),0,100)
	result.detail_view_size=clampf(float(result.detail_view_size),50,2000)
	result.facade_view_size=clampf(float(result.facade_view_size),30,float(result.detail_view_size))
	result.detail_distance=clampf(float(result.detail_distance),50,1500)
	result.animation_full_distance=clampf(float(result.animation_full_distance),10,200)
	result.animation_medium_distance=clampf(float(result.animation_medium_distance),float(result.animation_full_distance)+10,600)
	result.animation_medium_interval=clampf(float(result.animation_medium_interval),.05,.5)
	result.animation_far_interval=clampf(float(result.animation_far_interval),result.animation_medium_interval,.8)
	result.occlusion_alpha=clampf(float(result.occlusion_alpha),.05,.8)
	result.fade_seconds=clampf(float(result.fade_seconds),.05,2)
	result.restore_delay=clampf(float(result.restore_delay),0,2)
	result.max_occlusion_layers=clampi(int(result.max_occlusion_layers),1,64)
	return result
static func load_options() -> Dictionary:
	if cached.is_empty():
		var data: Variant=JSON.parse_string(FileAccess.get_file_as_string(PATH))
		cached=normalize(data if data is Dictionary else {})
	return cached.duplicate(true)
