extends RefCounted
## Continuous SAT for translating oriented boxes. Includes parked cars and wrecks.
## Broad phase uses swept AABBs; vertical clearance separates bridge traffic.
static func body_position(v: Dictionary) -> Vector2:
	return v.get("body_position",v.position)

static func direction(v: Dictionary) -> Vector2:
	return Vector2.from_angle(float(v.get("heading",0)))

static func radius_on(v: Dictionary, axis: Vector2) -> float:
	var forward:=direction(v)
	return absf(forward.dot(axis))*float(v.get("length",40))*.5+absf(forward.orthogonal().dot(axis))*float(v.get("width",18))*.5

static func contact(a: Dictionary, a_start: Vector2, a_end: Vector2, b: Dictionary, b_start: Vector2, b_end: Vector2) -> Dictionary:
	if a.get("stored_in","")!="" or b.get("stored_in","")!="": return {}
	if absf(float(a.get("height",0))-float(b.get("height",0)))>maxf(float(a.get("body_height",1.5)),float(b.get("body_height",1.5))): return {}
	var separation: Vector2=b_start-a_start
	var relative: Vector2=(b_end-b_start)-(a_end-a_start)
	var entry:=0.0
	var exit:=1.0
	var normal:=Vector2.ZERO
	var penetration:=INF
	var overlap_axis:=Vector2.ZERO
	var initially_overlapping:=true
	for axis in [direction(a),direction(a).orthogonal(),direction(b),direction(b).orthogonal()]:
		var reach: float=radius_on(a,axis)+radius_on(b,axis)
		var distance: float=separation.dot(axis)
		var speed: float=relative.dot(axis)
		var depth: float=reach-absf(distance)
		if depth<penetration: penetration=depth; overlap_axis=axis*(1 if distance>=0 else -1)
		if depth<=.001: initially_overlapping=false
		if absf(speed)<.000001:
			if absf(distance)>=reach-.001: return {}
			continue
		var first: float=(-reach-distance)/speed
		var last: float=(reach-distance)/speed
		if first>last:
			var swap:=first; first=last; last=swap
		if first>entry:
			entry=first
			normal=axis*(1 if distance+speed*entry>=0 else -1)
		exit=minf(exit,last)
		if entry>exit: return {}
	if exit<0 or entry>1: return {}
	if initially_overlapping: normal=overlap_axis
	if normal.is_zero_approx(): return {}
	# Touching bodies moving apart do not create repeated collision events.
	if not initially_overlapping and relative.dot(normal)>=0: return {}
	return {"time":clampf(entry,0,1),"normal":normal,"penetration":maxf(0,penetration) if initially_overlapping else 0.0}

static func swept_bounds(v: Dictionary, start: Vector2, finish: Vector2) -> Rect2:
	var extent:=Vector2(radius_on(v,Vector2.RIGHT),radius_on(v,Vector2.DOWN))
	return Rect2(start-extent,extent*2).merge(Rect2(finish-extent,extent*2)).grow(.01)

static func candidates(vehicles: Array, previous: Dictionary) -> Array:
	var buckets: Dictionary={}
	var result: Array=[]
	var seen: Dictionary={}
	for v in vehicles:
		if v.status in ["REMOVED","DESTROYED"] or v.get("stored_in","")!="": continue
		var rect:=swept_bounds(v,previous.get(v.id,{}).get("body",body_position(v)),body_position(v))
		for x in range(int(floorf(rect.position.x/128)),int(floorf(rect.end.x/128))+1):
			for y in range(int(floorf(rect.position.y/128)),int(floorf(rect.end.y/128))+1):
				var cell:=Vector2i(x,y)
				for other in buckets.get(cell,[]):
					var key: String=other.id+":"+v.id if other.id<v.id else v.id+":"+other.id
					if not seen.has(key): result.append([other,v]); seen[key]=true
				if not buckets.has(cell): buckets[cell]=[]
				buckets[cell].append(v)
	return result
