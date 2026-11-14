extends VBoxContainer
## Generation controls are locked once the run starts; overlays remain available.
const Map=preload("res://scripts/city_map.gd")
var manager: Node
var view: Node
var seed_input: SpinBox
var area_input: SpinBox
var width_input: SpinBox
var apply_button: Button
var regenerate_button: Button
var readout: Label
var size_picker: OptionButton
var density_input: SpinBox
var vegetation_input: SpinBox
var status_label: Label
var path_input: LineEdit
var preview: Control
var seed_channels: Dictionary={}
var world_buttons: Array[Button]=[]

func configure(sim: Node, map_view: Node) -> void:
	manager=sim; view=map_view
	name="WorldGenerationControls"
	var title:=Label.new(); title.text="WORLD GENERATION / SEEDS"; add_child(title)
	seed_input=_number("Map seed",0,2147483646,1)
	size_picker=OptionButton.new()
	for preset in ["small","medium","large","very_large"]: size_picker.add_item(preset)
	size_picker.select(1); add_child(size_picker)
	density_input=_number("District / road density",.5,1.5,.1); density_input.value=1
	vegetation_input=_number("Vegetation density",0,2,.1); vegetation_input.value=1
	area_input=_number("Area multiplier (previous city)",1,3,.25)
	area_input.tooltip_text="Historical map compatibility. Procedural world dimensions use the size preset."
	width_input=_number("Road width multiplier",.75,1.5,.05)
	apply_button=Button.new(); apply_button.text="Apply settings / same seed"; add_child(apply_button)
	apply_button.pressed.connect(func(): _regenerate(int(seed_input.value)))
	regenerate_button=Button.new(); regenerate_button.text="Regenerate map / new seed"; add_child(regenerate_button)
	regenerate_button.pressed.connect(func():
		var rng:=RandomNumberGenerator.new(); rng.randomize()
		_regenerate(rng.randi_range(0,2147483646)))
	_world_button("Random world seed",func(): seed_input.value=manager.world.random_seed())
	_world_button("Generate map",func(): _generate())
	_world_button("Regenerate same world",func():
		if not manager.world.current.is_empty(): seed_input.value=manager.world.current.world_seed
		_generate())
	_world_button("Copy current world seed",func(): DisplayServer.clipboard_set(str(Map.map_seed)))
	world_buttons[-1].set_meta("lock_during_run",false)
	preview=preload("res://scripts/world_preview.gd").new(); add_child(preview)
	path_input=LineEdit.new(); path_input.text="user://worlds/exported_world.json"; path_input.placeholder_text="World JSON path"; add_child(path_input)
	_world_button("Save / export world configuration",func():
		status_label.text="Saved: "+ProjectSettings.globalize_path(path_input.text) if manager.world.save_world(path_input.text) else manager.world.error)
	world_buttons[-1].set_meta("lock_during_run",false)
	_world_button("Load saved world configuration",func():
		if manager.phase=="PREPARATION": manager.world.load_world(path_input.text))
	for channel in ["population","scenario","events","behavior"]:
		var input:=_number(channel.capitalize()+" seed (-1 inherits scenario seed)",-1,2147483646,1)
		input.value=-1; seed_channels[channel]=input
	_world_button("Apply experiment seeds / keep this world",func():
		if manager.phase!="PREPARATION": return
		for channel in seed_channels: manager.experiment_seeds[channel]=int(seed_channels[channel].value)
		manager.initialize_run())
	status_label=Label.new(); status_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; add_child(status_label)
	manager.world.status_changed.connect(func(message: String): status_label.text=message)
	var districts:=CheckBox.new(); districts.text="Show city districts"; add_child(districts)
	districts.toggled.connect(func(value): Map.generation_settings.show_districts=value; manager.city_settings.show_districts=value)
	var graph:=CheckBox.new(); graph.text="Navigation graph / F8"; add_child(graph)
	graph.toggled.connect(func(value): manager.set_meta("road_debug",value))
	var spaces:=CheckBox.new(); spaces.text="Parking occupancy (red / green)"; add_child(spaces)
	spaces.toggled.connect(func(value): Map.generation_settings.show_parking=value; manager.city_settings.show_parking=value)
	var focus:=Button.new(); focus.text="Focus Alder Court"; add_child(focus)
	focus.pressed.connect(func():
		view.camera_rig.focus_at(preload("res://scripts/three_d/world_coordinates.gd").to_world(Map.grove.center))
		view.camera_rig.target_distance=150)
	readout=Label.new(); readout.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; readout.custom_minimum_size.x=275; add_child(readout)
	manager.run_initialized.connect(sync)

func _world_button(title: String, action: Callable) -> void:
	var button:=Button.new(); button.text=title; add_child(button); button.pressed.connect(action); world_buttons.append(button)

func _generate() -> void:
	if manager.phase!="PREPARATION" or manager.world.busy: return
	manager.generate_world(int(seed_input.value),{"preset":size_picker.get_item_text(size_picker.selected),
		"district_density":density_input.value,"vegetation_density":vegetation_input.value,"road_width_multiplier":width_input.value})

func _number(title: String, minimum: float, maximum: float, step: float) -> SpinBox:
	var label:=Label.new(); label.text=title; add_child(label)
	var input:=SpinBox.new(); input.min_value=minimum; input.max_value=maximum; input.step=step; add_child(input)
	return input

func _regenerate(seed_value: int) -> void:
	if manager.phase!="PREPARATION": return
	if not manager.world.current.is_empty():
		seed_input.value=seed_value; _generate(); return
	manager.city_settings.area_multiplier=area_input.value
	manager.city_settings.road_width_multiplier=width_input.value
	manager.new_run(seed_value)

func sync() -> void:
	seed_input.set_value_no_signal(Map.map_seed)
	for channel in seed_channels: seed_channels[channel].set_value_no_signal(manager.experiment_seeds.get(channel,-1))
	if not manager.world.current.is_empty():
		area_input.hide(); get_child(area_input.get_index()-1).hide()
		var settings: Dictionary=manager.world.current.settings
		for i in range(size_picker.item_count):
			if size_picker.get_item_text(i)==settings.preset: size_picker.select(i)
		density_input.set_value_no_signal(settings.district_density); vegetation_input.set_value_no_signal(settings.vegetation_density)
	status_label.text=manager.world.status
	preview.queue_redraw()
	area_input.set_value_no_signal(manager.city_settings.area_multiplier)
	width_input.set_value_no_signal(Map.generation_settings.road_width_multiplier)
	var estimates: Dictionary=Map.travel_estimates(Map.nearest_lane_point(Map.MAP_SIZE*.5))
	readout.text="World seed %d | %.0f x %.0f m\nValidated: %d junctions / %d roads\n%d buildings / %d parking spaces\nReference ETAs from city centre:\nWalk 1.4 m/s; drive 9.5 m/s"%[Map.map_seed,Map.MAP_SIZE.x*.1,Map.MAP_SIZE.y*.1,Map.graph.get_point_count(),Map.roads.size(),Map.lots.size(),int(Map.validation.parking_spaces)]
	for id in estimates:
		var value: Dictionary=estimates[id]
		readout.text+="\n%s: %.0f m, %.0f s / %.0f m, %.0f s"%[id,value.walk_metres,value.walk_seconds,value.drive_metres,value.drive_seconds]

func _process(_delta: float) -> void:
	if manager==null: return
	var editable: bool=manager.phase=="PREPARATION" and not manager.world.busy
	for input in [seed_input,area_input,width_input,density_input,vegetation_input]+seed_channels.values(): input.editable=editable
	size_picker.disabled=not editable
	for button in world_buttons: button.disabled=not editable if button.get_meta("lock_during_run",true) else manager.world.busy
	apply_button.disabled=not editable; regenerate_button.disabled=not editable
