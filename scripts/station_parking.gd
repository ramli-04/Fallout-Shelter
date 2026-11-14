extends RefCounted
## UV registration of the parking already painted into the current station art.
## No second asphalt parcel is drawn. Simulation bays still own departures.
static func configure(map: Script) -> void:
	for lot in map.parking_lots:
		if lot.category not in ["police","offices"]: continue
		var kind: String="Police Station" if lot.category=="police" else "Fire Station"
		var index: int=-1
		for poi in map.pois:
			if poi.kind==kind: index=map.lots.find(poi.footprint); break
		if index<0: continue
		lot.integrated_station=true
		lot.allowed_vehicle_kind="Police" if lot.category=="police" else "Fire"
		var fire: bool=lot.category=="offices"
		var width: float=36.0 if fire else 34.0
		var height: float=width*(403.0/489.0 if fire else 323.0/413.0)
		var ground_depth: float=width*.45
		var anchor: float=(height*.47-ground_depth*.5)/.8660254
		var center_uv:=Vector2(.41,.76) if fire else Vector2(.335,.765)
		var ground_center: float=.97-ground_depth/(2*height)
		var facing: int=posmod(roundi(map.lot_angles[index]/(PI*.5)),4)
		var mirror: bool=facing in [1,2]
		var old_center:=Vector2.ZERO
		for bay in lot.bays: old_center+=bay.position
		old_center/=lot.bays.size()
		var origin: Vector2=old_center-offset(center_uv,width,height,ground_center,mirror)
		map.building_data[index]["station_art"]={"width":width,"height":height,"anchor":anchor,"ground_depth":ground_depth,"offset":(origin-map.lots[index].get_center())*.1}
		var bays: Array=[]
		for i in range(3 if fire else 6):
			var uv:=Vector2(.25+i*.16,.67+i*.09) if fire else Vector2(.17+i*.066,.67+i*.038)
			var position: Vector2=origin+offset(uv,width,height,ground_center,mirror)
			var outward: Vector2=offset(uv+Vector2(-.08,.065),width,height,ground_center,mirror)-offset(uv,width,height,ground_center,mirror)
			var heading: float=outward.angle()
			var direction:=outward.normalized()
			var clearance: float=190.0 if fire else 70.0
			var aisle: Vector2=position+direction*clearance
			var line_origin: Vector2=old_center+direction*clearance
			var line_tangent:=direction.orthogonal()
			var gate: Vector2=line_origin+line_tangent*(lot.road_entry-line_origin).dot(line_tangent)
			var bay: Dictionary=lot.bays[i].duplicate(true)
			bay.position=position; bay.heading=heading
			bay.approach=PackedVector2Array([lot.road_entry,gate,aisle,position])
			bay.length=90 if fire else 60; bay.width=30
			bays.append(bay)
		lot.bays=bays
		for bay in bays: lot.bounds=lot.bounds.expand(bay.position).expand(bay.approach[-2]).expand(bay.approach[1])

static func offset(uv: Vector2,width: float,height: float,ground_center: float,mirror: bool) -> Vector2:
	var sx: float=((1.0-uv.x if mirror else uv.x)-.5)*width
	var down: float=(uv.y-ground_center)*height
	return Vector2(sx+down/.5,-sx+down/.5)/sqrt(2.0)/.1

static func allows(lot: Dictionary,vehicle: Dictionary) -> bool:
	var restricted: String=str(lot.get("allowed_vehicle_kind",""))
	if not restricted.is_empty(): return vehicle.get("kind","")==restricted
	return true
