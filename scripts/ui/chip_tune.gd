class_name ChipTune
extends Node
## 8-битная мелодия для бумбокса: оригинальный короткий мотив (пентатоника ля минор), синтезируется кодом.
## Прямоугольная волна для мелодии, треугольная для баса; зацикливается. toggle() включает/выключает.

const MIX_RATE := 22050
const BPM := 120.0
## Полутоны от ля первой октавы; null-паузы обозначены -99.
const MELODY: Array[int] = [12, 15, 19, 15, 17, 15, 12, 10, 12, 15, 19, 22, 19, 17, 15, 17, -99, 19, 17, 15, 12, 15, 10, 12]
const BASS: Array[int] = [-12, -12, -5, -5, -7, -7, -10, -10]

var _player: AudioStreamPlayer
var _stream: AudioStreamWAV


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.volume_db = -8.0
	add_child(_player)


func is_playing() -> bool:
	return _player != null and _player.playing


## Возвращает true, если музыка теперь играет.
func toggle() -> bool:
	if _player.playing:
		_player.stop()
		return false
	if _stream == null:
		_stream = _build()
	_player.stream = _stream
	_player.play()
	return true


static func _freq(semitones: int) -> float:
	return 220.0 * pow(2.0, float(semitones) / 12.0)


static func _build() -> AudioStreamWAV:
	var step := 60.0 / BPM / 2.0 # восьмая
	var steps := MELODY.size()
	var per_step := int(MIX_RATE * step)
	var bytes := PackedByteArray()
	bytes.resize(per_step * steps * 2)
	for i in steps:
		var note := MELODY[i]
		var bass := BASS[(i / 3) % BASS.size()]
		for j in per_step:
			var t := float(j) / float(MIX_RATE)
			var env := exp(-3.2 * float(j) / float(per_step))
			var value := 0.0
			if note != -99:
				var phase := fmod(t * _freq(note), 1.0)
				value += (0.5 if phase < 0.5 else -0.5) * env
			var bphase := fmod(t * _freq(bass), 1.0)
			value += (absf(bphase * 4.0 - 2.0) - 1.0) * 0.45
			bytes.encode_s16((i * per_step + j) * 2, int(clampf(value * 0.55, -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = bytes
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = per_step * steps
	return stream
