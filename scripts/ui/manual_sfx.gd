class_name ManualSfx
extends Node
## Звуки-заглушки ручного приготовления: короткие тоны/шум, синтезируются кодом (без файлов).
## Позже заменяются настоящими записями, интерфейс play(имя) останется тем же.

const MIX_RATE := 22050
const POOL_SIZE := 3

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next_player: int = 0


func _ready() -> void:
	for i in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		add_child(player)
		_players.append(player)


## sound: drop, pack, foil, hole, coal, light, done, bad.
func play(sound: String) -> void:
	if _players.is_empty():
		return
	var stream := stream_for(sound)
	if stream == null:
		return
	var player := _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	player.stream = stream
	player.play()


func stream_for(sound: String) -> AudioStreamWAV:
	if _streams.has(sound):
		return _streams[sound]
	var data := PackedByteArray()
	match sound:
		"drop":
			data = _tone(520.0, 0.09, 0.35, 0.0)
		"pack":
			data = _tone(170.0, 0.05, 0.25, 0.8)
		"foil":
			data = _tone(950.0, 0.12, 0.22, 0.9)
		"hole":
			data = _tone(720.0, 0.07, 0.4, 0.15)
		"coal":
			data = _tone(140.0, 0.14, 0.5, 0.3)
		"light":
			data = _tone(320.0, 0.16, 0.2, 0.9)
		"done":
			data = _tone(520.0, 0.12, 0.35, 0.0)
			data.append_array(_tone(780.0, 0.2, 0.35, 0.0))
		"bad":
			data = _tone(120.0, 0.3, 0.4, 0.2)
		_:
			return null
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = data
	_streams[sound] = stream
	return stream


## 16-битный моно PCM: синус + шум с затухающей огибающей.
static func _tone(frequency: float, seconds: float, volume: float, noise: float) -> PackedByteArray:
	var count := int(MIX_RATE * seconds)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	for i in count:
		var t := float(i) / float(MIX_RATE)
		var envelope := exp(-5.0 * t / seconds)
		var value := sin(TAU * frequency * t) * (1.0 - noise) + randf_range(-1.0, 1.0) * noise
		bytes.encode_s16(i * 2, int(clampf(value * envelope * volume, -1.0, 1.0) * 32767.0))
	return bytes
