class_name AmbientAudio
extends AudioStreamPlayer
## Sonido ambiental sintetizado en tiempo real (sin archivos de audio): viento en planetas,
## olas en la costa y zumbido de maquinaria en estaciones y en el vacío.

enum Kind { WIND, WAVES, HUM }

const MIX_RATE := 22050.0

var kind: Kind = Kind.WIND
var _playback: AudioStreamGeneratorPlayback
var _brown := 0.0
var _t := 0.0


static func for_location(def: Dictionary) -> AmbientAudio:
	var a := AmbientAudio.new()
	if StationBuilder.is_space(def) or def.get("kind", "") == "anomaly_zone":
		a.kind = Kind.HUM
	elif def.get("biome", "") == "ocean" or def.get("kind", "") == "town":
		a.kind = Kind.WAVES
	return a


func _ready() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = MIX_RATE
	gen.buffer_length = 0.25
	stream = gen
	volume_db = -12.0
	play()
	_playback = get_stream_playback() as AudioStreamGeneratorPlayback


func _process(_delta: float) -> void:
	if _playback == null:
		return
	for i in _playback.get_frames_available():
		_t += 1.0 / MIX_RATE
		_brown = clampf(_brown + randf_range(-1.0, 1.0) * 0.02, -1.0, 1.0) * 0.998
		var s := 0.0
		match kind:
			Kind.WIND:
				s = _brown * (0.45 + 0.4 * sin(_t * 0.31) * sin(_t * 0.13))
			Kind.WAVES:
				s = _brown * (0.25 + 0.75 * pow(maxf(sin(_t * 0.55), 0.0), 2.0))
			Kind.HUM:
				s = sin(TAU * 55.0 * _t) * 0.18 + sin(TAU * 110.0 * _t) * 0.06 + _brown * 0.25
		_playback.push_frame(Vector2(s, s))
