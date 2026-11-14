extends PanelContainer
var manager: Node
var text: Label
var sound: AudioStreamPlayer
var delivered := 0
func _ready() -> void:
	add_theme_stylebox_override("panel",preload("res://scripts/dashboard.gd").style(Color("fff4da"),Color("b98145")))
	text=Label.new(); text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; text.custom_minimum_size=Vector2(350,70); text.add_theme_font_size_override("font_size",13); text.add_theme_color_override("font_color",Color("3e493f")); add_child(text)
	sound=AudioStreamPlayer.new(); sound.volume_db=-20; add_child(sound)
	var stream:=AudioStreamWAV.new(); stream.format=AudioStreamWAV.FORMAT_16_BITS; stream.mix_rate=22050
	var data:=PackedByteArray(); data.resize(4410*2)
	for i in range(4410):
		var t:=float(i)/22050
		var wave: float=sin(TAU*(880 if t<.1 else 1175)*t)*.3*sin(PI*t/.2)
		data.encode_s16(i*2,int(wave*32767))
	stream.data=data; sound.stream=stream
	hide()
func _process(_delta: float) -> void:
	if manager==null or manager.social==null: hide(); return
	var social: RefCounted=manager.social
	if social.alerts.is_empty(): hide(); delivered=0; return
	var alert: Dictionary=social.alerts[-1]
	visible=manager.elapsed_seconds<=alert.expires
	text.text="ESSAIM CIVIL DEFENSE ALERT\n%s · %s\n%s\n%s\nReached %d devices (Director view)"%[alert.severity,alert.issuer,alert.message,alert.instructions,alert.recipients.size()]
	if social.counters.alerts_delivered>delivered:
		if not social.replaying: sound.play()
	delivered=social.counters.alerts_delivered
