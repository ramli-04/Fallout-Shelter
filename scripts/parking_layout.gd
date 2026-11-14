extends RefCounted
## Parking is zoned before buildings, sharing the seeded road geometry.
static func generate(roads: Array, size: Vector2, park: Rect2, lake: Rect2, rocks: Array, sites: Dictionary, count: int, seed_value: int) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	var order: Array=roads.duplicate()
	var random:=RandomNumberGenerator.new(); random.seed=seed_value+61003
	for i in range(order.size()-1,0,-1):
		var j:=random.randi_range(0,i); var swap: Variant=order[i]; order[i]=order[j]; order[j]=swap
	for road in order:
		if road.trail or road.get("elevated",false) or road.get("ramp",false): continue
		var points: PackedVector2Array=road.points
		for index in range(3,points.size()-3,5):
			if result.size()>=count: return result
			var origin: Vector2=points[index]
			var tangent: Vector2=(points[index+1]-points[index-1]).normalized()
			for sign_value in [-1,1]:
				if result.size()>=count: return result
				var normal: Vector2=tangent.orthogonal()*sign_value
				var polygon:=PackedVector2Array([origin-tangent*112+normal*50,origin+tangent*112+normal*50,origin+tangent*112+normal*175,origin-tangent*112+normal*175])
				var bounds:=Rect2(polygon[0],Vector2.ZERO)
				for p in polygon: bounds=bounds.expand(p)
				if not Rect2(Vector2.ONE*20,size-Vector2.ONE*40).encloses(bounds) or park.grow(10).intersects(bounds) or lake.grow(20).intersects(bounds): continue
				var clear:=true
				for rock in rocks:
					if rock.grow(10).intersects(bounds): clear=false
				for site in sites.values():
					if bounds.grow(100).has_point(site): clear=false
				for existing in result:
					if existing.bounds.grow(25).intersects(bounds): clear=false
				if not clear: continue
				for other in roads:
					if other.get("elevated",false): continue
					for p in other.points:
						if not bounds.grow(45).has_point(p): continue
						var delta: Vector2=p-origin
						if absf(delta.dot(tangent))<152 and delta.dot(normal)>10 and delta.dot(normal)<215: clear=false; break
					if not clear: break
				if not clear: continue
				var id: String="PARK%03d"%result.size()
				var bays: Array=[]
				for bay in range(6):
					var along: float=(bay-2.5)*35
					bays.append({"id":id+":%d"%bay,"position":origin+tangent*along+normal*130,"heading":(-normal).angle(),"occupied_by":"","approach":PackedVector2Array([origin,origin+normal*40,origin+tangent*along+normal*40,origin+tangent*along+normal*130])})
				result.append({"id":id,"position":origin+normal*110,"road_entry":origin,"tangent":tangent,"normal":normal,"polygon":polygon,"bounds":bounds,"bays":bays})
	return result
