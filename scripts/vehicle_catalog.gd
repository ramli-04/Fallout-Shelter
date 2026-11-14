extends RefCounted
## Dimensions are simulation units (10 units = one rendered metre).
const CIVILIAN := ["hatchback","sedan","suv","pickup","van","delivery_truck","minibus","motorcycle"]
const TYPES := {
	"hatchback":{"length":35.0,"width":17.0,"height":1.45,"capacity":4,"mass":1100.0,"max_speed":100.0,"acceleration":32.0,"braking":70.0},
	"sedan":{"length":43.0,"width":18.0,"height":1.5,"capacity":5,"mass":1450.0,"max_speed":110.0,"acceleration":30.0,"braking":70.0},
	"suv":{"length":47.0,"width":20.0,"height":1.85,"capacity":5,"mass":1900.0,"max_speed":100.0,"acceleration":25.0,"braking":66.0},
	"pickup":{"length":52.0,"width":20.0,"height":1.8,"capacity":4,"mass":2000.0,"max_speed":95.0,"acceleration":23.0,"braking":64.0},
	"van":{"length":53.0,"width":21.0,"height":2.3,"capacity":7,"mass":2300.0,"max_speed":90.0,"acceleration":21.0,"braking":60.0},
	"delivery_truck":{"length":70.0,"width":24.0,"height":3.1,"capacity":2,"mass":4800.0,"max_speed":80.0,"acceleration":16.0,"braking":54.0},
	"minibus":{"length":75.0,"width":24.0,"height":2.8,"capacity":12,"mass":5200.0,"max_speed":85.0,"acceleration":17.0,"braking":55.0},
	"motorcycle":{"length":23.0,"width":9.0,"height":1.25,"capacity":2,"mass":250.0,"max_speed":110.0,"acceleration":40.0,"braking":75.0},
	"swat":{"length":57.0,"width":22.0,"height":2.4,"capacity":6,"mass":4000.0,"max_speed":100.0,"acceleration":24.0,"braking":70.0},
	"police":{"length":44.0,"width":19.0,"height":1.6,"capacity":5,"mass":1600.0,"max_speed":115.0,"acceleration":34.0,"braking":76.0},
	"ambulance":{"length":61.0,"width":22.0,"height":2.6,"capacity":5,"mass":3500.0,"max_speed":105.0,"acceleration":24.0,"braking":65.0},
	"fire_engine":{"length":85.0,"width":25.0,"height":3.0,"capacity":6,"mass":11000.0,"max_speed":90.0,"acceleration":16.0,"braking":57.0},
	"rescue_truck":{"length":62.0,"width":23.0,"height":2.5,"capacity":6,"mass":4500.0,"max_speed":100.0,"acceleration":22.0,"braking":62.0}
}

static func choose(kind: String, rng: RandomNumberGenerator) -> String:
	if kind=="Police": return "swat" if rng.randf()<.35 else "police"
	if kind!="Civilian": return {"Police":"police","Medical":"ambulance","Fire":"fire_engine","Civil protection":"rescue_truck"}.get(kind,"sedan")
	var draw:=rng.randf()
	var weights: Array=[.22,.25,.17,.1,.1,.06,.05,.05]
	for i in range(weights.size()):
		draw-=weights[i]
		if draw<=0: return CIVILIAN[i]
	return "sedan"
