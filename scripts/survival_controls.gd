extends VBoxContainer
var manager: Node
var details: RichTextLabel
var refresh_age:=0.0
func setup(owner: Node) -> void:
	manager=owner; size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var title:=Label.new(); title.text="Ten-day survival · Director controls"; add_child(title)
	var controls:=HBoxContainer.new(); add_child(controls)
	for item in [["Pause",func():manager.pause()],["Resume",func():manager.start()],["Next important event",func():manager.survival.forward()]]:
		var b:=Button.new(); b.text=item[0]; b.pressed.connect(item[1]); controls.add_child(b)
	for speed in [1,5,20,50]:
		var b:=Button.new(); b.text="%d×"%speed; b.pressed.connect(func():manager.set_speed(speed)); controls.add_child(b)
	var info:=Label.new(); info.text="Opening conditions are fictional scenario inputs, not radiation safety advice.\nNext event advances in small steps; stops at an event transition, death, or daily report."; add_child(info)
	var selector:=OptionButton.new(); selector.add_item("All shelters")
	for id in ["S1","S2","S3","S4","S5"]: selector.add_item(id)
	add_child(selector)
	var fields: Dictionary={}
	for key in manager.survival.opening:
		var row:=HBoxContainer.new(); add_child(row)
		var label:=Label.new(); label.text=key.replace("_"," ").capitalize(); label.custom_minimum_size.x=260; row.add_child(label)
		if manager.survival.opening[key] is bool:
			var input:=CheckBox.new(); input.button_pressed=manager.survival.opening[key]; row.add_child(input); fields[key]=input
		else:
			var input:=SpinBox.new(); input.max_value=30 if key=="minimum_day" else 1; input.step=1 if key=="minimum_day" else .05; input.value=manager.survival.opening[key]; row.add_child(input); fields[key]=input
	selector.item_selected.connect(func(index):
		var policy: Dictionary=manager.survival.opening.duplicate(); policy.merge(manager.survival.overrides.get("S%d"%index,{}),true)
		for key in fields:
			if fields[key] is CheckBox: fields[key].button_pressed=policy[key]
			else: fields[key].value=policy[key])
	var status:=Label.new(); add_child(status)
	var apply:=Button.new(); apply.text="Apply opening conditions"; add_child(apply)
	apply.pressed.connect(func():
		var values: Dictionary={}
		for key in fields: values[key]=fields[key].button_pressed if fields[key] is CheckBox else fields[key].value
		status.text="Conditions applied" if manager.survival.configure("" if selector.selected==0 else selector.get_item_text(selector.selected),values) else "Conditions cannot be changed in replay or after final evaluation")
	var export_button:=Button.new(); export_button.text="Export results and comparison charts"; add_child(export_button)
	export_button.pressed.connect(func():
		var path: String=manager.survival.export_report()
		status.text="Complete Day 10 before exporting" if path.is_empty() else "Exported JSON; chart generation started in "+path.get_base_dir())
	var open_button:=Button.new(); open_button.text="Open report folder"; add_child(open_button)
	open_button.pressed.connect(func():
		if not manager.survival.export_path.is_empty(): OS.shell_open(manager.survival.export_path.get_base_dir()))
	details=RichTextLabel.new(); details.custom_minimum_size=Vector2(730,400); details.fit_content=true; add_child(details)

func _process(delta: float) -> void:
	refresh_age+=delta
	if manager==null or details==null or refresh_age<1: return
	refresh_age=0
	var run=manager.survival
	if not run.started: details.text="The survival clock begins at impact."; return
	details.text="Shelter Day %d / 10 · %.2f simulated days · %d daily reports\n"%[mini(10,int(run.elapsed_days())+1),run.elapsed_days(),run.reports.size()]
	for report in run.reports: details.text+="Day %d: %d survivors · %d deaths · %d injured · %d missing\n"%[report.day,report.population.survivors,report.population.deaths,report.population.injuries,report.population.missing]
	for id in run.result.get("shelters",{}):
		var s: Dictionary=run.result.shelters[id]
		details.text+="\n%s · %d occupants · %s\n%s\n"%[id,s.occupancy,s.opening.status,", ".join(s.opening.reasons)]
