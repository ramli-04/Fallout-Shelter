extends Node
## Compatibility facade: the spatial network owns playback. No second global siren loop.
var player: AudioStreamPlayer
var network: Node3D
func configure(view: Node) -> void:
	network = view.siren_network
	player = network.director_player
func sound_siren() -> void:
	if network: network.sync_mix()
func set_clock_active(_elapsed: float, _active: bool) -> void:
	if network: network.sync_mix()
func stop_siren() -> void:
	if player: player.stop()
