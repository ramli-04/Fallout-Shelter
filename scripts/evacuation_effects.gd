extends Node
## Generated warning sound. No simulation rules or downloaded audio.

var player: AudioStreamPlayer


func _ready() -> void:
	player = AudioStreamPlayer.new()
	player.volume_db = -15
	add_child(player)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 11025
	var samples := PackedByteArray()
	samples.resize(11025 * 3 * 2)
	var phase := 0.0
	for index in range(11025 * 3):
		var time := float(index) / 11025
		var frequency := 500 + 220 * sin(TAU * time / 1.2)
		phase += TAU * frequency / 11025
		var fade := minf(1, time * 10) * minf(1, (3 - time) * 5)
		samples.encode_s16(index * 2, int(sin(phase) * fade * 14000))
	stream.data = samples
	player.stream = stream


func sound_siren() -> void:
	player.stream_paused = false
	player.play()


func set_clock_active(_elapsed: float, active: bool) -> void:
	player.stream_paused = not active


func stop_siren() -> void:
	player.stop()
