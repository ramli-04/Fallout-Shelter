extends RefCounted
## Shared deterministic structural recipe for persistent physics and streamed art.
const Map=preload("res://scripts/city_map.gd")
static func plan(index: int) -> Dictionary:
	var rect: Rect2=Map.lots[index]
	var size: Vector2=Map._v2(Map.building_data[index].get("local_size",[rect.size.x*.67,rect.size.y*.67]))*.1
	var rng:=RandomNumberGenerator.new(); rng.seed=Map.map_seed+index*173+701
	var palette: Array=[Color("887d67"),Color("967357"),Color("737b70"),Color("687778"),Color("8d8875"),Color("826452")]
	var color: Color=palette[int(Map.building_data[index].get("asset_variant",rng.randi_range(0,5)))%6]
	color=color.darkened(float(Map.building_data[index].get("weathering",0))*.16)
	var result: Dictionary={"size":size,"height":float(Map.building_data[index].get("height_m",5.2)),"color":color,"wings":[],"roof":false,"chimneys":false,"terrace":false,
		"perimeter":Map.building_data[index].get("style","")=="perimeter","interior":Map.interior_data.get("I%04d"%index,{})}
	for poi in Map.pois:
		if poi.footprint==rect and poi.kind=="Medical Station": result.height=22.0
	if not result.interior.is_empty() and result.interior.active: return result
	result.interior={}
	var w: float=size.x; var d: float=size.y; var h: float=result.height
	var style:=rng.randi_range(0,4); var civic:=false
	for poi in Map.pois:
		if poi.footprint!=rect: continue
		civic=true; h=float({"School":6.4,"Medical Station":22.0,"Fire Station":9.0,"Police Station":7.0,"Bank":18.0}.get(poi.kind,6.4)); style=2
		color=Color({"Police Station":"9cbdcd","Fire Station":"c66e60","Medical Station":"e6ecda","Bank":"b1bda6","School":"d9b578"}[poi.kind])
	var district: String=Map.lot_districts[index]
	if civic:
		result.height=maxf(h,6.4); result.wings=[[Vector3(w,result.height,d),Vector3.ZERO,color]]; result.color=color
		for poi in Map.pois:
			if poi.footprint==rect and poi.kind=="Fire Station":
				result.wings=[[Vector3(w*.78,5.8,d),Vector3(-w*.11,0,0),color],[Vector3(w*.22,result.height,d*.65),Vector3(w*.39,0,-d*.175),color]]
		return result
	if result.perimeter: result.wings=[[Vector3(w,h,d),Vector3.ZERO,color]]; return result
	if not civic and (district=="GROVE" or (district=="RESIDENTIAL" and rng.randf()<.70)):
		h=rng.randf_range(3.2,6.0); result.roof=true; result.wings=[[Vector3(w,h,d),Vector3.ZERO,color]]
	elif not civic and district=="INDUSTRIAL":
		h=rng.randf_range(4,7); result.chimneys=true; result.wings=[[Vector3(w,h,d),Vector3.ZERO,Color("89958b")]]
	else:
		result.terrace=true
		match style:
			0: result.wings=[[Vector3(w*.43,h,d),Vector3(-w*.285,0,0),color],[Vector3(w*.57,h*.65,d*.38),Vector3(w*.215,0,d*.31),color.lightened(.06)]]
			1: result.wings=[[Vector3(w,h*.2,d),Vector3.ZERO,color],[Vector3(w*.64,h*.8,d*.64),Vector3(0,h*.2,0),color.darkened(.08)]]
			2:
				result.wings=[[Vector3(w,h,d*.32),Vector3(0,0,-d*.34),color]]
				for side in [-1,1]: result.wings.append([Vector3(w*.27,h*.85,d*.68),Vector3(side*w*.365,0,d*.16),color])
			3: result.wings=[[Vector3(w*.62,h,d),Vector3(-w*.19,0,0),color],[Vector3(w*.38,h*.6,d*.78),Vector3(w*.31,0,d*.11),color.lightened(.08)]]
			_: result.wings=[[Vector3(w,h*.4,d),Vector3.ZERO,color],[Vector3(w*.78,h*.35,d*.72),Vector3(-w*.08,h*.4,0),color.lightened(.04)],[Vector3(w*.5,h*.25,d*.48),Vector3(-w*.16,h*.75,0),color.darkened(.08)]]
	result.height=h; result.color=color
	return result

static func boxes(recipe: Dictionary) -> Array:
	var result: Array=[]
	if recipe.interior.is_empty():
		for wing in recipe.wings: result.append({"size":wing[0],"position":wing[1]+Vector3(0,wing[0].y*.5,0),"door":false})
		return result
	var size: Vector2=recipe.size; var normal: Vector2=recipe.interior.door_normal
	for side in [Vector2.RIGHT,Vector2.LEFT,Vector2.DOWN,Vector2.UP]:
		var length: float=size.y if side.x else size.x; var extent: float=(size.x if side.x else size.y)*.5
		if side==normal:
			for sign_value in [-1,1]:
				var offset: Vector2=side*extent+side.orthogonal()*sign_value*(length+1.6)*.25
				result.append({"size":Vector3(.18,3.2,(length-1.6)*.5) if side.x else Vector3((length-1.6)*.5,3.2,.18),"position":Vector3(offset.x,1.6,offset.y),"door":false})
		else: result.append({"size":Vector3(.18,3.2,length) if side.x else Vector3(length,3.2,.18),"position":Vector3(side.x*extent,1.6,side.y*extent),"door":false})
	var point: Vector2=normal*(size.x if normal.x else size.y)*.5
	result.append({"size":Vector3(.16,2.2,1.6) if normal.x else Vector3(1.6,2.2,.16),"position":Vector3(point.x,1.1,point.y),"door":true})
	if recipe.height>3.5: result.append({"size":Vector3(size.x,recipe.height-3.2,size.y),"position":Vector3(0,(recipe.height+3.2)*.5,0),"door":false})
	return result
