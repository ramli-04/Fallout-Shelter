extends VBoxContainer
## Director-only controls exercise the same storyteller and physical response paths.
var manager: Node
var target: OptionButton
var kind: OptionButton
var severity: SpinBox
var selected_event: OptionButton
var responder: OptionButton
var paused: CheckBox
var status: Label
var audit: RichTextLabel
var detail: Label
var age:=0.0

func configure(value: Node) -> void:
	manager=value; name="ShelterStorytellerControls"
	var title:=Label.new(); title.text="SHELTER STORYTELLER / MANUAL TEST CONTROLS"; add_child(title)
	var explanation:=Label.new(); explanation.text="Available during shelter life. Manual events are labeled in history.\nResponses require knowledge, skills and arrival at the event room."; explanation.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; add_child(explanation)
	target=OptionButton.new()
	for id in ["S1","S2","S3","S4","S5"]: target.add_item(id)
	add_child(target)
	kind=OptionButton.new()
	var configuration: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://resources/shelter_storyteller.json"))
	var keys: Array=configuration.events.keys(); keys.sort()
	for key in keys: kind.add_item(str(key).replace("_"," ").capitalize()); kind.set_item_metadata(kind.item_count-1,key)
	add_child(kind)
	var label:=Label.new(); label.text="Severity (0.01–1.00)"; add_child(label)
	severity=SpinBox.new(); severity.min_value=.01; severity.max_value=1; severity.step=.05; severity.value=.3; add_child(severity)
	_button("Trigger shelter event [MANUAL TEST]",func():
		var story=manager.social.shelter_life.storyteller
		var id: String=story.trigger(str(kind.get_selected_metadata()),target.get_item_text(target.selected),severity.value,true)
		status.text="[MANUAL TEST] Triggered "+id if not id.is_empty() else story.last_error
		refresh())
	paused=CheckBox.new(); paused.text="Pause automatic shelter events (active hazards continue)"; add_child(paused)
	paused.toggled.connect(func(value):
		var story=manager.social.shelter_life.storyteller
		if story.config.is_empty(): status.text="Enter shelter life before changing event generation."; return
		story.pause_generation(value))
	selected_event=OptionButton.new(); add_child(selected_event)
	detail=Label.new(); detail.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; add_child(detail)
	_button("Adjust selected severity [MANUAL TEST]",func():
		status.text="Manual severity adjustment applied" if manager.social.shelter_life.storyteller.adjust_severity(_event_id(),severity.value) else "Select an active event"; refresh())
	responder=OptionButton.new(); add_child(responder)
	_button("Test selected resident response (walk to event)",func():
		var actor: Dictionary=_actor()
		status.text="Response assigned; resident must arrive before work counts" if not actor.is_empty() and manager.social.shelter_life.storyteller.request_response(_event_id(),actor) else "Response refused: check knowledge, skill, stress, route and needs")
	_button("Commander: request physical shelter transfer",func():
		var actor: Dictionary=_actor()
		status.text="Transfer ordered through the existing evacuation system" if not actor.is_empty() and manager.social.shelter_life.storyteller.order_transfer(_event_id(),actor) else "No verified reachable destination, accessible exit, or informed commander in contact")
	status=Label.new(); status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; status.text="Enter the shelter phase to test events."; add_child(status)
	audit=RichTextLabel.new(); audit.custom_minimum_size.y=260; audit.fit_content=true; add_child(audit)
	refresh()

func _button(title: String,action: Callable) -> void:
	var button:=Button.new(); button.text=title; add_child(button); button.pressed.connect(action)

func _event_id() -> String:
	return str(selected_event.get_selected_metadata()) if selected_event.selected>=0 else ""

func _actor() -> Dictionary:
	return manager.social.by_id.get(str(responder.get_selected_metadata()),{}) if responder.selected>=0 else {}

func _process(seconds: float) -> void:
	age+=seconds
	if age>=1: age=0; refresh()

func refresh() -> void:
	if manager.social==null: return
	var story=manager.social.shelter_life.storyteller
	var saved_event:=_event_id(); var saved_actor: String=str(responder.get_selected_metadata()) if responder.selected>=0 else ""
	selected_event.clear(); responder.clear()
	for event in story.events:
		selected_event.add_item("%s / %s / %s / %.2f / %s / %s"%[event.event_id,event.target_id,event.event_type,event.severity,event.status,event.origin]); selected_event.set_item_metadata(selected_event.item_count-1,event.event_id)
		if event.event_id==saved_event: selected_event.select(selected_event.item_count-1)
	for a in manager.agents:
		if not a.get("shelter_life_active",false) or a.get("health",0)<=0: continue
		responder.add_item("%s / %s / %s / %s"%[a.get("display_name",a.id),a.get("occupation",""),a.get("shelter_id",""),a.get("shelter_room_id","")]); responder.set_item_metadata(responder.item_count-1,a.id)
		if a.id==saved_actor: responder.select(responder.item_count-1)
	paused.set_pressed_no_signal(story.generation_paused)
	var event: Dictionary=story.find(_event_id())
	detail.text="Select an event to inspect its room, severity and response progress."
	if not event.is_empty(): detail.text="%s / room %s / severity %.2f\nWork %.2f / %.2f simulated hours / informed residents %s\nResponders: %s"%[event.origin,event.room_id,event.severity,event.progress,event.work_required,str(event.visibility_to_agents),str(event.responders)]
	audit.text="Selected event history (Director / recorded):\n"
	for entry in story.history:
		if entry.event_id==_event_id() or entry.event_id.is_empty(): audit.text+="%.2fh / %s / %s / %s / %s\n"%[entry.hour,entry.event_id,entry.kind,entry.action,entry.origin]
