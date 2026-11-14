extends SceneTree
const V=preload("res://scripts/generation/building_validator.gd")
var failures:=0
func check(value: bool,label: String) -> void:
	if not value: failures+=1; printerr(label)
func _initialize() -> void:
	var data={"nodes":[[0,0],[1000,0]],"roads":[{"from":0,"to":1,"points":[[0,0],[1000,0]],"width":40,"sidewalk":10}],"buildings":[{"rect":[100,100,100,100],"road_entry":[150,0],"access_path":[[150,0],[150,100]],"parcel":[[100,100],[200,100],[200,200],[100,200]]}]}
	check(V.validate(data).valid,"valid connected parcel rejected")
	var overlapping=data.duplicate(true); overlapping.buildings.append(data.buildings[0].duplicate(true))
	check(V.validate(overlapping).overlapping_buildings==1,"overlap accepted")
	var blocked=data.duplicate(true); blocked.buildings.append({"rect":[130,45,40,40],"driveway":[]})
	check(V.validate(blocked).inaccessible_entrances==1,"blocked access accepted")
	var road=data.duplicate(true); road.buildings[0].rect=[100,-10,100,100]
	check(not V.validate(road).valid,"road encroachment accepted")
	var disconnected=data.duplicate(true); disconnected.nodes.append([2000,2000])
	check(V.validate(disconnected).road_components==2,"disconnected node accepted")
	var frontage=data.duplicate(true); frontage.buildings[0].road_entry=[150,70]
	check(not V.validate(frontage).valid,"disconnected frontage accepted")
	print("Godot placement: 6 checks / %d failures"%failures); quit(1 if failures else 0)
