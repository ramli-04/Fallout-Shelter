extends VBoxContainer
## Director inspection uses actual dispatch records, including pending requests.
var manager: Node
var picker: OptionButton
var details: RichTextLabel
var elapsed:=0.0

func configure(value: Node) -> void:
	manager=value; name="PoliceControls"
	var title:=Label.new(); title.text="POLICE DISPATCH / ROADBLOCK INSPECTION"; add_child(title)
	picker=OptionButton.new(); add_child(picker)
	picker.item_selected.connect(func(_index):refresh())
	details=RichTextLabel.new(); details.custom_minimum_size.y=260; details.bbcode_enabled=false; add_child(details)
	refresh()

func _process(delta: float) -> void:
	elapsed+=delta
	if elapsed>=.5: elapsed=0; refresh()

func refresh() -> void:
	if manager==null or manager.social==null: return
	var police: RefCounted=manager.social.police
	var selected: String=str(picker.get_item_metadata(picker.selected)) if picker.selected>=0 else ""
	if picker.item_count!=police.requests.size()+1:
		picker.clear(); picker.add_item("All units and requests"); picker.set_item_metadata(0,"")
		for r in police.requests:
			picker.add_item(r.id); picker.set_item_metadata(picker.item_count-1,r.id)
			if r.id==selected: picker.select(picker.item_count-1)
	details.text=police.inspection(selected)+manager.social.evacuation.inspection(str(police.request_for(selected).get("operation","")))
