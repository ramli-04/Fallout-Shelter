extends CanvasLayer
var controller: Control
var manager: Node
var backdrop: ColorRect
var menu: VBoxContainer
var loading: VBoxContainer
var bar: ProgressBar
var stage: Label
var seed_input: SpinBox
var busy:=false
func setup(owner_node: Control,simulation: Node) -> void:
	controller=owner_node; manager=simulation; layer=80
	backdrop=ColorRect.new(); backdrop.color=Color("18251f"); backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(backdrop)
	var center:=CenterContainer.new(); center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); backdrop.add_child(center)
	var panel:=PanelContainer.new(); panel.custom_minimum_size=Vector2(520,380); center.add_child(panel)
	var margin:=MarginContainer.new(); for side in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,32)
	panel.add_child(margin); var stack:=VBoxContainer.new(); stack.add_theme_constant_override("separation",18); margin.add_child(stack)
	var title:=Label.new(); title.text="ESSAIM"; title.add_theme_font_size_override("font_size",38); stack.add_child(title)
	menu=VBoxContainer.new(); menu.add_theme_constant_override("separation",12); stack.add_child(menu)
	var label:=Label.new(); label.text="City and survival simulation / World seed"; menu.add_child(label)
	seed_input=SpinBox.new(); seed_input.min_value=0; seed_input.max_value=2147483646; seed_input.value=42; menu.add_child(seed_input)
	button("Generate and enter city",func(): manager.world.current.clear(); controller._start_map_view())
	button("Resume city",func():
		if not manager.agents.is_empty(): hide(); manager.start())
	button("Scenario settings",func(): hide(); controller._show_drawer("settings"))
	button("Quit",func(): get_tree().quit())
	loading=VBoxContainer.new(); loading.add_theme_constant_override("separation",16); stack.add_child(loading)
	stage=Label.new(); stage.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; loading.add_child(stage)
	bar=ProgressBar.new(); bar.custom_minimum_size=Vector2(420,28); bar.show_percentage=true; loading.add_child(bar)
	loading.hide()
	manager.world.progress_changed.connect(func(value: int,name: String):
		if busy: report(value*.70,"Map generation: "+name.capitalize()))
func button(text: String,callback: Callable) -> void:
	var node:=Button.new(); node.text=text; node.custom_minimum_size.y=42; node.pressed.connect(callback); menu.add_child(node)
func begin() -> void:
	busy=true; show(); menu.hide(); loading.show(); bar.value=0; stage.text="Preparing world generation"
func report(value: float,text: String) -> void:
	bar.value=maxf(bar.value,value); stage.text=text
func fail(message: String) -> void:
	busy=false; stage.text=message; menu.show(); loading.show()
func finish() -> void:
	report(100,"Ready"); await get_tree().process_frame; busy=false; hide(); menu.show(); loading.hide()
func open() -> void:
	if busy: return
	manager.pause(); show(); menu.show(); loading.hide()
