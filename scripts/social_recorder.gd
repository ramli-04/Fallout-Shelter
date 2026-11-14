extends RefCounted
## Serialize snapshots and write the append-only audit off the render thread.
var worker := Thread.new()
var wake := Semaphore.new()
var lock := Mutex.new()
var queue: Array = []
var stopping := false
func start(path: String) -> void: worker.start(_write_loop.bind(path))
func enqueue(packet: Dictionary) -> void:
	var copy:=packet.duplicate(true)
	lock.lock(); queue.append(copy); lock.unlock(); wake.post()
func close() -> void:
	if not worker.is_started(): return
	lock.lock(); stopping=true; lock.unlock(); wake.post()
	worker.wait_to_finish()
func _write_loop(path: String) -> void:
	var file:=FileAccess.open(path,FileAccess.WRITE)
	if file==null: return
	while true:
		wake.wait()
		lock.lock()
		var batch: Array=queue
		queue=[]
		var finished: bool=stopping
		lock.unlock()
		for packet in batch: file.store_line(JSON.stringify(encode(packet),"",true,true))
		file.flush()
		if finished: break
	file.close()
static func encode(value: Variant) -> Variant:
	if value is float and not is_finite(value): return {"__float":"inf" if value>0 else "-inf"}
	if value is Vector2: return {"__v2":[value.x,value.y]}
	if value is PackedVector2Array:
		var points:=[]
		for p in value: points.append([p.x,p.y])
		return {"__route":points}
	if value is Dictionary:
		var result: Dictionary={}
		for key in value: result[str(key)]=encode(value[key])
		return result
	if value is Array:
		var result: Array=[]
		for item in value: result.append(encode(item))
		return result
	return value
