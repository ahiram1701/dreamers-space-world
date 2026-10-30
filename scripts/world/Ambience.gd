class_name Ambience
extends Node
## Sonido de fondo según la hora y el sitio: pájaros de día, grillos de noche, murmullo de gente
## en la cafetería y una música suave de acordes sintetizados que cambia con el momento del día.
## Todo se genera al vuelo (el juego no lleva archivos de audio).

var scene: LocationScene

var _music: AudioStreamPlayer
var _murmur: AudioStreamPlayer
var _music_key := ""
var _t := 0.0
static var _cache := {}


func _ready() -> void:
	_music = AudioStreamPlayer.new()
	_music.volume_db = -80.0
	add_child(_music)
	_murmur = AudioStreamPlayer.new()
	_murmur.stream = _noise_loop(3.0, 0.08)
	_murmur.volume_db = -80.0
	add_child(_murmur)


func _process(delta: float) -> void:
	_t += delta
	var inside := scene._interiors.is_inside()
	var night := WorldClock.night() > 0.5
	# Música: una progresión de día y otra de noche, con fundido al cambiar
	var key := "night" if night else "day"
	if key != _music_key:
		_music_key = key
		_music.stream = _pad(key)
		_music.play()
	var target := linear_to_db(maxf(Settings.music_volume * 0.35, 0.0001))
	_music.volume_db = lerpf(_music.volume_db, target, 1.0 - exp(-0.8 * delta))
	# Murmullo de gente dentro de la cafetería (si hay alguien)
	var busy := inside and scene._interiors.current_kind() in ["cafe", "shop"] and WorldClock.hour() > 8.0 and WorldClock.hour() < 21.0
	if busy and not _murmur.playing:
		_murmur.play()
	_murmur.volume_db = lerpf(_murmur.volume_db, -22.0 if busy else -80.0, 1.0 - exp(-1.5 * delta))
	# Pájaros y grillos, de vez en cuando, fuera
	if _t > 2.5 and not inside and not Weather.is_raining():
		_t = 0.0
		var at: Vector3 = scene._player.global_position + Vector3(randf_range(-14, 14), randf_range(3, 8), randf_range(-14, 14))
		if night and randf() < 0.7:
			_play3d(_cricket(), at, -16.0)
		elif not night and WorldClock.hour() > 5.5 and randf() < 0.5:
			_play3d(_bird(), at, -12.0)


func _play3d(stream: AudioStream, at: Vector3, db: float) -> void:
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.volume_db = db
	p.pitch_scale = randf_range(0.9, 1.15)
	p.unit_size = 6.0
	scene.add_child(p)
	p.global_position = at
	p.finished.connect(p.queue_free)
	p.play()


# --- Síntesis -------------------------------------------------------------------------------

const RATE := 22050


static func _wav(samples: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 28000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_end = samples.size()
	return w


## Trino: dos o tres silbidos cortos que suben.
static func _bird() -> AudioStreamWAV:
	var key := "bird%d" % (randi() % 3)
	if _cache.has(key):
		return _cache[key]
	var s := PackedFloat32Array()
	var notes := randi_range(2, 4)
	var base := randf_range(2600.0, 3600.0)
	var phase := 0.0
	for n in notes:
		var len := int(RATE * randf_range(0.06, 0.11))
		for i in len:
			var t := float(i) / len
			phase += TAU * (base + 1400.0 * t) / RATE
			s.append(sin(phase) * sin(PI * t) * 0.5)
		for i in int(RATE * 0.04):
			s.append(0.0)
	_cache[key] = _wav(s, false)
	return _cache[key]


## Grillo: trenes de pulsos agudos.
static func _cricket() -> AudioStreamWAV:
	if _cache.has("cricket"):
		return _cache.cricket
	var s := PackedFloat32Array()
	for pulse in 6:
		for i in int(RATE * 0.025):
			var t := float(i) / RATE
			s.append(sin(TAU * 4600.0 * t) * sin(PI * t / 0.025) * 0.4)
		for i in int(RATE * 0.02):
			s.append(0.0)
	_cache.cricket = _wav(s, false)
	return _cache.cricket


## Murmullo: ruido suave filtrado en bucle.
static func _noise_loop(seconds: float, amount: float) -> AudioStreamWAV:
	var s := PackedFloat32Array()
	var lp := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in int(RATE * seconds):
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.04)
		s.append(lp * amount * 6.0 * (0.7 + 0.3 * sin(float(i) / RATE * 1.7)))
	return _wav(s, true)


## Música: acordes largos y suaves (4 acordes de 6 s, en bucle).
static func _pad(kind: String) -> AudioStreamWAV:
	if _cache.has("pad_" + kind):
		return _cache["pad_" + kind]
	var chords := [[261.6, 329.6, 392.0], [196.0, 246.9, 293.7], [220.0, 261.6, 329.6], [174.6, 220.0, 261.6]] if kind == "day" \
		else [[220.0, 261.6, 329.6], [174.6, 220.0, 261.6], [146.8, 174.6, 220.0], [164.8, 207.7, 246.9]]
	var s := PackedFloat32Array()
	var per := int(RATE * 6.0)
	for c in chords:
		for i in per:
			var t := float(i) / RATE
			var env := minf(t / 1.5, 1.0) * minf((6.0 - t) / 1.5, 1.0)
			var v := 0.0
			for f in c:
				v += sin(TAU * f * t) * 0.18 + sin(TAU * f * 2.0 * t + 0.4) * 0.04
			s.append(v * env * (0.85 + 0.15 * sin(TAU * 0.2 * t)))
	_cache["pad_" + kind] = _wav(s, true)
	return _cache["pad_" + kind]
