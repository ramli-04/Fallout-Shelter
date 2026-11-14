extends VBoxContainer
## Director controls enqueue real events; they never edit occupancy or positions.
const Coordinates=preload("res://scripts/three_d/world_coordinates.gd")
var manager: Node
var view: Node
var kind: OptionButton
var target: OptionButton
var duration: SpinBox
var radius: SpinBox
var status: Label
var last_event:=""

func configure(sim: Node, map: Node) -> void:
	name="EmergencyControls"
	manager=sim; view=map
	var title:=Label.new(); title.text="DYNAMIC EMERGENCIES"; add_child(title)
	kind=OptionButton.new()
	for event in manager.emergency.TYPES: kind.add_item(event.replace("_"," ").capitalize())
	add_child(kind)
	target=OptionButton.new(); target.add_item("At camera focus")
	for id in ["S1","S2","S3","S4","S5"]: target.add_item(id)
	add_child(target)
	duration=_number("Duration (simulation seconds)",1,3600,60)
	radius=_number("Affected radius (map units)",5,500,60)
	kind.item_selected.connect(func(index):
		if manager.emergency.TYPES[index]=="POLICE_SHELTER_EVACUATION":
			duration.value=maxf(duration.value,1200); radius.value=maxf(radius.value,250)
			status.text="Police evacuation uses camera focus as the affected area; a selected shelter is a destination preference.")
	var inject:=Button.new(); inject.text="Trigger emergency"; add_child(inject)
	inject.pressed.connect(trigger)
	var clear:=Button.new(); clear.text="Clear last triggered event"; add_child(clear)
	clear.pressed.connect(func():
		status.text="Event cleared" if manager.emergency.clear_event(last_event) else "No active event to clear")
	_operation("Open selected shelter admissions","admit")
	_operation("Close selected shelter admissions","close")
	_operation("Open selected shelter exit only","exit")
	status=Label.new(); status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; status.text="Start the simulation, then choose an event and location."; add_child(status)
	manager.run_initialized.connect(func():last_event=""; status.text="New run: no emergency selected")

func _operation(title: String, operation: String) -> void:
	var button:=Button.new(); button.text=title; add_child(button)
	button.pressed.connect(func():
		if target.selected==0: status.text="Choose a shelter target first."; return
		var id: String=target.get_item_text(target.selected)
		var accepted: bool=manager.emergency.open_exit(id) if operation=="exit" else manager.emergency.set_admissions(id,operation=="admit")
		status.text=id+": operation applied" if accepted else id+": current shelter conditions prevent this operation")

func _number(title: String, minimum: float, maximum: float, value: float) -> SpinBox:
	var label:=Label.new(); label.text=title; add_child(label)
	var input:=SpinBox.new(); input.min_value=minimum; input.max_value=maximum; input.value=value; add_child(input)
	return input

func trigger() -> void:
	if not manager.running: status.text="Start or resume the simulation first."; return
	var type: String=manager.emergency.TYPES[kind.selected]
	var point: Vector2=Coordinates.to_simulation(view.camera_rig.target_focus)
	var options: Dictionary={"duration":duration.value,"radius":radius.value}
	if target.selected>0:
		var id: String=target.get_item_text(target.selected)
		if type!="POLICE_SHELTER_EVACUATION": point=manager.shelter_by_id[id].position
		options.shelter_id=id
	if type=="increasing_threat": options.severity=.2; options.growth_per_second=.01
	if type=="accident":
		var nearest: Dictionary={}; var distance:=INF
		for v in manager.social.vehicles:
			if v.status in ["ACCIDENT","REMOVED","DESTROYED"]: continue
			if v.position.distance_to(point)<distance: nearest=v; distance=v.position.distance_to(point)
		if nearest.is_empty(): status.text="No vehicle is available for an accident event."; return
		point=nearest.position; options.vehicle_id=nearest.id
	last_event=manager.add_emergency(type,point,options)
	status.text="Triggered "+type.replace("_"," ")+" ("+last_event+")" if not last_event.is_empty() else "Event rejected; check the location and settings."
