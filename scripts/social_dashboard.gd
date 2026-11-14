extends Window
const Dashboard=preload("res://scripts/dashboard.gd")
const Config = preload("res://scripts/social_config.gd")
var manager: Node
var launch: Callable
var fields := {}
var feedback: Label
var metrics: Label
var histogram: Control
var stress_histogram: Control
var ai_details: Label
var emergency_locations: Label
var authority_details: Label
var replay_slider: HSlider
var refresh_age := 0.0
var loading := false
var preset_picker: OptionButton

func setup(owner_manager: Node, start_action: Callable) -> void:
	manager=owner_manager; launch=start_action
	title="ESSAIM / CONFIGURE SIMULATION"
	size=Vector2i(900,780); min_size=Vector2i(700,500)
	close_requested.connect(hide)
	var background:=ColorRect.new(); background.color=Color("f2f5ed"); background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); background.mouse_filter=Control.MOUSE_FILTER_IGNORE; add_child(background)
	var root := VBoxContainer.new(); root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(root)
	root.offset_left=12; root.offset_right=-12; root.offset_top=8; root.offset_bottom=-8
	var tabs := TabContainer.new(); tabs.size_flags_vertical=Control.SIZE_EXPAND_FILL; root.add_child(tabs)
	var scroll := ScrollContainer.new(); scroll.name="Configuration"; tabs.add_child(scroll)
	var form := VBoxContainer.new(); form.size_flags_horizontal=Control.SIZE_EXPAND_FILL; scroll.add_child(form)
	var explanation := Label.new(); explanation.text="Apply before starting. Civilian count = total − authorities. IQ is a synthetic experimental variable.\nProvider groups A/B/C use backend configuration; cloud calls require existing backend opt-in."; form.add_child(explanation)
	var defaults := Config.defaults()
	for key in defaults:
		if key=="schema_version": continue
		if key in ["total","iq_mean","stress_tolerance","vehicle_rate","phone_rate","warning_min","llm_agents","execution_mode","group_a","provider_a","pre_disaster_seconds","named_agents_enabled"]:
			var heading:=Label.new(); heading.text={"total":"POPULATION","iq_mean":"SYNTHETIC INTELLIGENCE","stress_tolerance":"PERSONALITY AVERAGES","vehicle_rate":"TRANSPORT","phone_rate":"COMMUNICATION","warning_min":"SIMULATION","llm_agents":"AI SCHEDULING","execution_mode":"EXECUTION","group_a":"AGENT GROUP ASSIGNMENTS","provider_a":"PROVIDERS / MODELS","pre_disaster_seconds":"DAILY CITY / BEFORE THE WARNING","named_agents_enabled":"NAMED AGENTS / COMPANION"}[key]; form.add_child(heading)
		var row := HBoxContainer.new(); form.add_child(row)
		var label := Label.new(); label.text="Roadblock initiative (evidence threshold)" if key=="roadblock_frequency" else key.replace("_"," ").capitalize(); label.custom_minimum_size.x=290; row.add_child(label)
		var value: Variant = defaults[key]
		if key.begins_with("model_"):
			var input:=LineEdit.new(); input.text=value; input.custom_minimum_size.x=230; row.add_child(input); fields[key]=input
		elif value is bool:
			var input := CheckBox.new(); input.button_pressed=value; row.add_child(input); fields[key]=input
		elif value is String:
			var input := OptionButton.new()
			for option in (["async","sync"] if key=="execution_mode" else ["ollama","gemini","grok","openai"] if key.begins_with("provider_") else ["A","B","C","rules"]): input.add_item(option)
			row.add_child(input); fields[key]=input
		else:
			var input := SpinBox.new(); input.min_value=18 if key in ["zack_age","legend_age"] else 0; input.max_value=100 if key in ["zack_age","legend_age"] else 2147483647 if key=="seed" else 10000
			input.step=1 if key in Config.INTEGER_KEYS else .01; input.value=value;
			if value is float and value>=0 and value<=1: input.tooltip_text="Fraction from 0 to 1: 0.6 means 60%"
			input.custom_minimum_size.x=170
			row.add_child(input); fields[key]=input
		if fields[key] is SpinBox: fields[key].value_changed.connect(_field_changed.bind(key))
	feedback=Label.new(); feedback.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; root.add_child(feedback)
	var buttons := HBoxContainer.new(); root.add_child(buttons)
	for entry in [["START SIMULATION",_start],["SAVE PRESET",_save],["LOAD PRESET",_load],["RESET DEFAULTS",func():set_config(Config.defaults())]]:
		var b := Dashboard.button(entry[0]); b.pressed.connect(entry[1]); buttons.add_child(b)
	var experiments := HBoxContainer.new(); form.add_child(experiments)
	preset_picker=OptionButton.new()
	for name in ["A No phones","B Phones","C Social media","D High rumors","E High trust","F Low trust","G Roadblocks","H Congestion","I Family priority","J Individual priority","K Mixed AI","L Sync","L Async"]: preset_picker.add_item(name)
	experiments.add_child(preset_picker)
	var experiment_button := Dashboard.button("APPLY EXPERIMENT"); experiments.add_child(experiment_button); experiment_button.pressed.connect(_experiment)
	var director_scroll := ScrollContainer.new(); director_scroll.name="Director · omniscient"; tabs.add_child(director_scroll)
	var director := VBoxContainer.new(); director.size_flags_horizontal=Control.SIZE_EXPAND_FILL; director_scroll.add_child(director)
	var results_scroll:=ScrollContainer.new(); results_scroll.name="Survival results"; tabs.add_child(results_scroll)
	var results_controls=preload("res://scripts/survival_controls.gd").new(); results_scroll.add_child(results_controls); results_controls.setup(manager)
	var shelter_event_scroll:=ScrollContainer.new(); shelter_event_scroll.name="Shelter events"; tabs.add_child(shelter_event_scroll)
	var shelter_event_controls=preload("res://scripts/shelter_event_controls.gd").new()
	shelter_event_scroll.add_child(shelter_event_controls); shelter_event_controls.size_flags_horizontal=Control.SIZE_EXPAND_FILL; shelter_event_controls.configure(manager)
	metrics=Label.new(); metrics.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; director.add_child(metrics)
	authority_details=Label.new(); authority_details.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; authority_details.text="Authority coordination starts with the simulation."; director.add_child(authority_details)
	histogram=preload("res://scripts/population_histogram.gd").new(); director.add_child(histogram)
	stress_histogram=preload("res://scripts/population_histogram.gd").new(); director.add_child(stress_histogram)
	emergency_locations=Label.new(); director.add_child(emergency_locations)
	ai_details=Label.new(); ai_details.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; director.add_child(ai_details)
	var transport := Label.new(); transport.text="Transport / selected agent knowledge is in the agent inspector.\nF8 toggles the physical road graph, closures and vehicle identifiers."; director.add_child(transport)
	var debug := CheckBox.new(); debug.text="Road network debug (Director only)"; director.add_child(debug); debug.toggled.connect(func(v): manager.set_meta("road_debug",v))
	var driving_ai:=CheckBox.new(); driving_ai.text="OpenJev overtaking decisions"; driving_ai.button_pressed=manager.get_meta("driving_ai",true); director.add_child(driving_ai)
	driving_ai.toggled.connect(func(value):
		manager.set_meta("driving_ai",value)
		if manager.social!=null:
			manager.social.driving.settings.ai_enabled=value
			if not value: manager.social.driving.close())
	var escape:=CheckBox.new(); escape.text="Emergency pavement escape (clear paths only)"; escape.button_pressed=manager.get_meta("pavement_escape",true); director.add_child(escape)
	escape.toggled.connect(func(value):
		manager.set_meta("pavement_escape",value)
		if manager.social!=null: manager.social.driving.settings.emergency_escape_enabled=value)
	var cutaways:=CheckBox.new(); cutaways.text="Show accessible building interiors (Director cutaway)"
	director.add_child(cutaways)
	cutaways.toggled.connect(func(value):preload("res://scripts/city_map.gd").interior_cutaway=value)
	var replay := Dashboard.button("LOAD RECORDED RUN (no LLM calls)"); director.add_child(replay)
	var dialog := FileDialog.new(); dialog.file_mode=FileDialog.FILE_MODE_OPEN_FILE; dialog.access=FileDialog.ACCESS_FILESYSTEM; dialog.filters=PackedStringArray(["*.jsonl ; Recorded run"]); add_child(dialog)
	replay.pressed.connect(func():dialog.current_dir=ProjectSettings.globalize_path("res://outputs/phase5"); dialog.popup_centered_ratio())
	dialog.file_selected.connect(_replay)
	replay_slider=HSlider.new(); replay_slider.step=1; director.add_child(replay_slider)
	replay_slider.value_changed.connect(func(v):
		if manager.social!=null and manager.social.replaying: manager.social.apply_replay_frame(int(v)))
	set_config(manager.social_config if not manager.social_config.is_empty() else defaults)
	hide()

func current() -> Dictionary:
	var c := Config.defaults()
	for key in fields:
		var field: Control=fields[key]
		if field is SpinBox: c[key]=int(field.value) if key in Config.INTEGER_KEYS else field.value
		elif field is LineEdit: c[key]=field.text
		elif field is CheckBox: c[key]=field.button_pressed
		elif field is OptionButton: c[key]=field.get_item_text(field.selected)
	c.civilians=c.total-c.authorities
	return c

func set_config(c: Dictionary) -> void:
	loading=true
	for key in fields:
		var field: Control=fields[key]
		if field is SpinBox: field.value=c[key]
		elif field is LineEdit: field.text=c[key]
		elif field is CheckBox: field.button_pressed=c[key]
		elif field is OptionButton:
			for i in range(field.item_count):
				if field.get_item_text(i)==c[key]: field.select(i)
	loading=false; _validate_form()

func _validate_form() -> void:
	if loading or feedback==null: return
	var c:=current()
	var error:=Config.validate(c)
	feedback.text=error if not error.is_empty() else "%d civilians + %d authorities = %d agents | %d LLM / %d rules"%[c.civilians,c.authorities,c.total,c.llm_agents,c.total-c.llm_agents]

func _start() -> void:
	if manager.world.busy:
		if not await manager.world.completed: feedback.text=manager.world.error; return
	if manager.running or manager.phase not in ["PREPARATION","IMPACT","ALL_CLEAR"]:
		feedback.text="Reset the current simulation before applying a new configuration."; return
	var c:=current()
	var error:=Config.validate(c)
	if not error.is_empty(): feedback.text=error; return
	if not await _apply_providers(c): return
	manager.phase5_enabled=true; manager.social_config=c; manager.seed_value=c.seed
	if manager.world.current.is_empty():
		manager.generate_world(manager.world.random_seed())
		if not await manager.world.completed: feedback.text=manager.world.error; return
	else: manager.initialize_run()
	if not manager.last_setup_error.is_empty(): feedback.text=manager.last_setup_error; return
	if manager.agents.size()!=c.total: feedback.text="Population initialization failed"; return
	hide(); launch.call()

func _save() -> void:
	var result:=Config.save_preset(current())
	feedback.text="Saved: "+ProjectSettings.globalize_path(Config.USER_PATH) if result==OK else "Invalid settings; preset not saved"

func _load() -> void:
	if not FileAccess.file_exists(Config.USER_PATH): feedback.text="No saved preset"; return
	var data: Variant=JSON.parse_string(FileAccess.get_file_as_string(Config.USER_PATH))
	if not data is Dictionary: feedback.text="Invalid JSON preset"; return
	var error:=Config.validate(data)
	if not error.is_empty(): feedback.text=error; return
	set_config(data)

func _experiment() -> void:
	var c:=current()
	match preset_picker.selected:
		0: c.phone_rate=0; c.social_adoption=0
		1: c.phone_rate=.95; c.social_adoption=0
		2: c.phone_rate=.95; c.social_adoption=.8
		3: c.rumor_probability=.9
		4: c.authority_trust=.9
		5: c.authority_trust=.1
		6: c.roadblock_frequency=.9
		7: c.vehicle_rate=.9; c.traffic_density=.95
		8: c.family_priority=.95
		9: c.family_priority=.05
		10: c.llm_agents=int(c.total/2)
		11: c.execution_mode="sync"
		12: c.execution_mode="async"
	set_config(c)

func _replay(path: String) -> void:
	# Read the recorded configuration first to recreate matching entities and geometry.
	var file:=FileAccess.open(path,FileAccess.READ)
	if file==null: feedback.text="Cannot open replay"; return
	var initial: Variant=null
	# Physical initialization can emit events before the complete run header.
	while not file.eof_reached():
		var packet: Variant=JSON.parse_string(file.get_line())
		if packet is Dictionary and packet.get("record_type","")=="initial":
			initial=packet; break
	file.close()
	if not initial is Dictionary or not initial.has("config") or not Config.validate(initial.config).is_empty(): feedback.text="Invalid replay header"; return
	if initial.get("world",{}).is_empty() and int(initial.get("map_version",0))!=preload("res://scripts/city_map.gd").layout_version:
		feedback.text="This recording uses an older city generator. Open it with its original project version."; return
	manager.pause(); manager.social_config=initial.config; manager.seed_value=int(initial.get("master_seed",initial.config.seed))
	manager.experiment_seeds=initial.get("experiment_seeds",{"population":-1,"scenario":-1,"events":-1,"behavior":-1})
	if initial.has("city_settings"): manager.city_settings=initial.city_settings
	if initial.has("map_scale"): manager.nuclear.map_scale=initial.map_scale
	if not initial.get("world",{}).is_empty():
		var world_file:=FileAccess.open("user://replay_world.json",FileAccess.WRITE)
		world_file.store_string(initial.get("world_json",JSON.stringify(initial.world))); world_file.close()
		if not manager.world.load_world("user://replay_world.json") or not await manager.world.completed:
			feedback.text="Recorded world failed validation"; return
	else:
		manager.world.current.clear()
		manager.initialize_run()
	if manager.social.load_replay(path):
		replay_slider.max_value=manager.social.replay_frames.size()-1; feedback.text="Replay loaded. Scrub timeline; simulation and inference are disabled."
	else: feedback.text="No complete frames found"

func _process(delta: float) -> void:
	if not visible or manager==null or manager.social==null: return
	refresh_age+=delta
	if refresh_age<1: return
	refresh_age=0
	metrics.text=manager.social.snapshot_text()
	authority_details.text=manager.social.authorities.director_text()
	ai_details.text=manager.ai_bridge.dashboard_text()
	histogram.values=manager.social.iq_stats.histogram
	histogram.title="Synthetic IQ · bins <55 / 55–70 / 70–85 / 85–100 / 100–115 / 115–130 / 130–145 / >145"
	histogram.queue_redraw()
	var measured: Dictionary=manager.social.experiment_metrics()
	stress_histogram.values=measured.stress_histogram; stress_histogram.title="Stress: bins 0-20 / 20-40 / 40-60 / 60-80 / 80-100"; stress_histogram.queue_redraw()
	metrics.text+="\nSurvival rate: %s | Mean shelter arrival: %s s\nUnique alert reach: %d | Stale family contacts: %d | Trust changes: %d\nConsensus among acquired claims: %s"%["pending impact" if measured.survival_rate==null else "%.1f%%"%(measured.survival_rate*100),"no arrivals" if measured.mean_shelter_arrival_seconds==null else "%.1f"%measured.mean_shelter_arrival_seconds,measured.alert_unique_reach,measured.stale_or_unknown_family_contacts,measured.trust_changes,"no shared evidence" if measured.consensus_among_acquired_beliefs==null else "%.1f%%"%(measured.consensus_among_acquired_beliefs*100)]
	emergency_locations.text="Emergency vehicle locations (Director):"
	var shelter_text: String=manager.social.shelter_life_text()
	if not shelter_text.is_empty(): metrics.text+="\n"+shelter_text
	for id in measured.shelter_social.councils:
		var council: Dictionary=measured.shelter_social.councils[id]
		if not council.leader.is_empty(): metrics.text+="\n%s representative: %s / support %.0f%% / work groups %d"%[id,council.leader,float(council.support)*100,council.groups.size()]
	for v in manager.social.vehicles:
		if v.kind!="Civilian": emergency_locations.text+="\n%s %s %s %s"%[v.id,v.kind,str(v.position),v.status]

func _apply_providers(c: Dictionary) -> bool:
	if c.llm_agents==0: return true
	var request:=HTTPRequest.new(); request.timeout=10; add_child(request)
	var groups: Dictionary={}
	for suffix in ["a","b","c"]: groups[suffix.to_upper()]={"provider":c["provider_"+suffix],"model":c["model_"+suffix],"concurrency":c.provider_concurrency}
	if request.request(manager.ai_config.service_url+"/social/providers",["Content-Type: application/json"],HTTPClient.METHOD_POST,JSON.stringify(groups))==OK:
		var result: Array=await request.request_completed
		if result[0]!=HTTPRequest.RESULT_SUCCESS or result[1]!=200:
			feedback.text="Provider configuration failed. Check backend/cloud opt-in or wait for current requests to finish."
			request.queue_free(); return false
	else:
		feedback.text="Could not contact AI backend"; request.queue_free(); return false
	request.queue_free()
	return true

func _field_changed(value: float, key: String) -> void:
	if loading: return
	loading=true
	if key=="civilians": fields.total.value=value+fields.authorities.value
	elif key in ["total","authorities"] and fields.has("civilians"): fields.civilians.value=maxf(0,fields.total.value-fields.authorities.value)
	loading=false; _validate_form()
