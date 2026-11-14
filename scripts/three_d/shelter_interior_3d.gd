extends Node3D
## Lightweight, presentation-only cutaway generated from a shelter-specific room plan.
## The simulation remains authoritative for shelter existence, supplies and capacity.
const Geometry = preload("res://scripts/three_d/geometry.gd")
const ROOM_W := 8.0
const ROOM_D := 6.0
const WALL_H := 2.5
const WALL_T := 0.16
const PLANS := {
	"S1": {"theme":"CIVILIAN REFUGE", "rooms":[["ENTRY","Entrance",0,0],["DORM-A","Dormitory",1,0],["DORM-B","Dormitory",2,0],["FAMILY","Family bedroom",3,0],["KITCHEN","Kitchen",0,1],["COMMON","Common room",1,1],["DINING","Dining",2,1],["FOOD","Food storage",3,1],["MEDICAL","Medical",0,2],["SANITATION","Sanitation",1,2],["RECREATION","Recreation",2,2],["GENERATOR","Generator",3,2]]},
	"S2": {"theme":"METRO VAULT", "rooms":[["ENTRY","Entrance",0,0],["CONCOURSE","Metro corridor",1,0],["PLATFORM","Dormitory",2,0],["STORAGE","Supply storage",3,0],["GENERATOR","Generator",0,1],["WATER","Water storage",1,1],["WORKSHOP","Workshop",2,1],["ELECTRICAL","Electrical",3,1],["SANITATION","Sanitation",0,2],["CONTROL","Control",1,2],["DINING","Dining",2,2],["AIR","Air filtration",3,2]]},
	"S3": {"theme":"COMMUNICATIONS", "rooms":[["ENTRY","Entrance",0,0],["OPERATIONS","Operations",1,0],["RADIO","Radio room",2,0],["COMMUNICATIONS","Communication",3,0],["MEDICAL","Medical",0,1],["CONTROL","Control",1,1],["AIR","Air filtration",2,1],["GENERATOR","Generator",3,1],["SANITATION","Sanitation",0,2],["WATER","Water treatment",1,2],["DINING","Dining",2,2],["FOOD","Food storage",3,2]]},
	"S4": {"theme":"MOUNTAIN SHELTER", "rooms":[["ENTRY","Entrance",0,0],["DORM-A","Dormitory",1,0],["DORM-B","Dormitory",2,0],["FAMILY","Family bedroom",3,0],["GENERATOR","Generator",0,1],["DINING","Dining",1,1],["FOOD","Food storage",2,1],["WORKSHOP","Industrial workshop",3,1],["SANITATION","Sanitation",0,2],["WATER","Water storage",1,2],["MEDICAL","Medical",2,2],["RECREATION","Recreation",3,2]]},
	"S5": {"theme":"RESTRICTED FACILITY", "rooms":[["ENTRY","Secure entrance",0,0],["CHECKPOINT","Security",1,0],["CONTROL","Control",2,0],["DORMITORY","Dormitory",3,0],["GENERATOR","Generator",0,1],["OPERATIONS","Operations",1,1],["COMMUNICATIONS","Communication",2,1],["STORAGE","Storage",3,1],["SANITATION","Sanitation",0,2],["MEDICAL","Medical",1,2],["DINING","Dining",2,2],["RECREATION","Recreation",3,2]]}
}
var shelter_id := ""
var rooms: Array[Dictionary] = []
var wall_nodes: Array[MeshInstance3D] = []
var room_nodes: Array[Node3D] = []
var selected_room := ""
var emergency := false
var lights: Array[OmniLight3D] = []

func configure(record: Dictionary) -> void:
	shelter_id = str(record.get("id", ""))
	if not record.get("exists", false) or not PLANS.has(shelter_id): return
	_build(PLANS[shelter_id])

func _build(plan: Dictionary) -> void:
	var base := 3.4
	Geometry.box(self, Vector3(34,0.22,19), Vector3(16,base-0.12,9), Color("343c3e"))
	Geometry.label(self, str(plan.theme), Vector3(16,base+3.0,-1.4), Color("e9d9b0"), 28, 0.025)
	for item in plan.rooms:
		var id := str(item[0]); var title := str(item[1]); var col := int(item[2]); var row := int(item[3])
		var origin := Vector3(col*ROOM_W,base,row*ROOM_D)
		var floor := Geometry.box(self,Vector3(ROOM_W-0.10,0.10,ROOM_D-0.10),origin+Vector3(ROOM_W/2,0,ROOM_D/2),Color("77756b"))
		floor.set_meta("room_id",id)
		var room_pick:=Area3D.new(); room_pick.position=origin+Vector3(ROOM_W/2,0.1,ROOM_D/2); room_pick.collision_layer=16; room_pick.collision_mask=0; room_pick.set_meta("room_id",id); room_pick.set_meta("room_owner",self); add_child(room_pick)
		var pick_shape:=CollisionShape3D.new(); var pick_box:=BoxShape3D.new(); pick_box.size=Vector3(ROOM_W-0.2,0.25,ROOM_D-0.2); pick_shape.shape=pick_box; room_pick.add_child(pick_shape)
		var room_data := {"id":id,"shelter_id":shelter_id,"type":title,"position":origin,"dimensions":Vector3(ROOM_W,ROOM_D,WALL_H),"capacity":_capacity(title),"doors":[],"furniture":[],"navigation_connections":[],"occupants":[],"functional":true}
		rooms.append(room_data)
		var marker := Node3D.new(); marker.position=origin+Vector3(ROOM_W/2,0.12,ROOM_D/2); marker.set_meta("room_id",id); add_child(marker); room_nodes.append(marker)
		var label := Geometry.label(self,id+"  "+title,origin+Vector3(ROOM_W/2,0.28,ROOM_D/2),Color("f3e9d5"),15,0.018); label.set_meta("room_id",id)
		# Each adjacent room pair shares a centered, walkable doorway gap.
		_add_x_wall(origin,0.0,_has_neighbor(plan,col,row,0,-1),id)
		if not _has_neighbor(plan,col,row,0,1): _add_x_wall(origin,ROOM_D,false,id)
		_add_z_wall(origin,0.0,_has_neighbor(plan,col,row,-1,0),id)
		if not _has_neighbor(plan,col,row,1,0): _add_z_wall(origin,ROOM_W,false,id)
		# Reusable benches / cabinets suggest room function without dense mesh counts.
		if title.contains("dorm") or title.contains("bedroom") or title.contains("Dormitory"):
			for bx in [2.0,5.8]: Geometry.box(self,Vector3(2.0,0.42,0.9),origin+Vector3(bx,0.36,3.0),Color("566c78"))
		elif title.contains("storage") or title.contains("warehouse") or title.contains("Food") or title.contains("Supply"):
			for bx in [2.0,5.8]: Geometry.box(self,Vector3(1.0,1.45,3.4),origin+Vector3(bx,0.82,3.0),Color("8d7656"))
		else: Geometry.box(self,Vector3(2.6,0.72,1.1),origin+Vector3(ROOM_W/2,0.50,ROOM_D/2),Color("596260"))
		var light := OmniLight3D.new(); light.position=origin+Vector3(ROOM_W/2,1.8,ROOM_D/2); light.light_color=Color("ffdca0"); light.light_energy=1.2; light.omni_range=8; add_child(light); lights.append(light)
		room_data.doors=[id+"-S"]
	for i in range(rooms.size()):
		for j in range(rooms.size()):
			if i==j: continue
			var delta: Vector3=rooms[i].position-rooms[j].position
			if (is_zero_approx(absf(delta.x)-ROOM_W) and is_zero_approx(delta.z)) or (is_zero_approx(absf(delta.z)-ROOM_D) and is_zero_approx(delta.x)):
				rooms[i].navigation_connections.append(rooms[j].id)

func _has_neighbor(plan: Dictionary,col: int,row: int,dc: int,dr: int) -> bool:
	for item in plan.rooms:
		if int(item[2])==col+dc and int(item[3])==row+dr: return true
	return false

func _add_x_wall(origin: Vector3,z: float,has_door: bool,room_id: String) -> void:
	if has_door:
		var segment: float=(ROOM_W-2.2)/2
		_add_wall(Vector3(segment,WALL_H,WALL_T),origin+Vector3(segment/2,WALL_H/2,z),room_id)
		_add_wall(Vector3(segment,WALL_H,WALL_T),origin+Vector3(ROOM_W-segment/2,WALL_H/2,z),room_id)
	else: _add_wall(Vector3(ROOM_W,WALL_H,WALL_T),origin+Vector3(ROOM_W/2,WALL_H/2,z),room_id)

func _add_z_wall(origin: Vector3,x: float,has_door: bool,room_id: String) -> void:
	if has_door:
		var segment: float=(ROOM_D-2.0)/2
		_add_wall(Vector3(WALL_T,WALL_H,segment),origin+Vector3(x,WALL_H/2,segment/2),room_id)
		_add_wall(Vector3(WALL_T,WALL_H,segment),origin+Vector3(x,WALL_H/2,ROOM_D-segment/2),room_id)
	else: _add_wall(Vector3(WALL_T,WALL_H,ROOM_D),origin+Vector3(x,WALL_H/2,ROOM_D/2),room_id)

func _add_wall(size: Vector3,at: Vector3,room_id: String) -> void:
	var wall:=Geometry.box(self,size,at,Color("8a8d87")); wall.set_meta("room_id",room_id); wall_nodes.append(wall)

func _capacity(title: String) -> int:
	var lower:=title.to_lower()
	if lower.contains("dorm"): return 32
	if lower.contains("bedroom"): return 8
	if lower.contains("dining") or lower.contains("common"): return 24
	return 6

func set_emergency_lighting(powered: bool) -> void:
	emergency = not powered
	for light in lights:
		light.light_color=Color("ff3349") if emergency else Color("ffdca0")
		light.light_energy=0.75 if emergency else 1.2

func select_room(room_id: String) -> Dictionary:
	selected_room=room_id
	for node in room_nodes:
		var active: bool=node.get_meta("room_id")==room_id
		node.scale=Vector3.ONE* (1.13 if active else 1.0)
	for room in rooms:
		if room.id==room_id: return room.duplicate(true)
	return {}

func update_cutaway(camera_position: Vector3) -> void:
	# Open the camera-facing perimeter; collision is deliberately unaffected.
	for wall in wall_nodes:
		var to_wall:=wall.global_position-camera_position
		wall.transparency=0.78 if camera_position.y>wall.global_position.y and to_wall.length()<70.0 else 0.0
