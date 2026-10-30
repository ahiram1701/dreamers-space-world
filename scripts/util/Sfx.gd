class_name Sfx
extends RefCounted
## Efectos de sonido sintetizados (el juego no lleva archivos de audio): avisos de la interfaz
## y sonidos del mundo (pasos según el suelo, puertas, golpes, hacha, agua). Los del mundo
## suenan en 3D desde donde ocurren.

static var _cache := {}

## Ruido filtrado por tipo: [duración s, caída (más = más seco), brillo 0..1, tono Hz (0 = sin tono), volumen dB]
const NOISES := {
	"step_grass": [0.09, 40.0, 0.25, 0.0, -20.0],
	"step_wood": [0.08, 45.0, 0.35, 140.0, -16.0],
	"step_stone": [0.06, 60.0, 0.55, 0.0, -18.0],
	"step_sand": [0.11, 30.0, 0.15, 0.0, -21.0],
	"step_water": [0.22, 14.0, 0.45, 0.0, -15.0],
	"knock": [0.07, 50.0, 0.3, 110.0, -6.0],
	"door": [0.35, 9.0, 0.2, 70.0, -12.0],
	"hit": [0.12, 30.0, 0.4, 90.0, -6.0],
	"chop": [0.1, 38.0, 0.6, 200.0, -8.0],
	"splash": [0.5, 7.0, 0.5, 0.0, -10.0],
	"whoosh": [0.25, 10.0, 0.7, 0.0, -18.0],
}


## Dos notas cortas y brillantes: "has recibido algo".
static func chime(parent: Node) -> void:
	_play(parent, "chime", _tone([880.0, 1318.5]))


## Una nota grave: "algo no ha salido".
static func deny(parent: Node) -> void:
	_play(parent, "deny", _tone([220.0]))


## Tres golpes en una puerta.
static func knock(parent: Node) -> void:
	for i in 3:
		_play(parent, "knock", null, -6.0, i * 0.22)


static func door(parent: Node) -> void:
	_play(parent, "door")


## Sonido del mundo en una posición (pasos, golpes, hacha…). `kind`: una clave de NOISES.
static func at(parent: Node, kind: String, pos: Vector3, pitch_jitter: float = 0.12) -> void:
	if not NOISES.has(kind) or not parent.is_inside_tree():
		return
	if not _cache.has(kind):
		_cache[kind] = _noise(NOISES[kind])
	var p := AudioStreamPlayer3D.new()
	p.stream = _cache[kind]
	p.volume_db = NOISES[kind][4] + 6.0
	p.unit_size = 4.0
	p.max_distance = 40.0
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	parent.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()


## Un paso de un personaje: el sonido depende de lo que pisa (hierba, arena, madera, agua).
static func footstep(body: CharacterBody3D, water_level: float = -INF) -> void:
	var pos := body.global_position
	var kind := "step_grass"
	if water_level > -INF and pos.y < water_level + 0.15 and pos.y > water_level - 8.0:
		kind = "step_water"
	else:
		var hit := body.get_last_slide_collision()
		var collider: Object = hit.get_collider() if hit else null
		if collider is CollisionObject3D:
			var shape: Shape3D = null
			for c in collider.get_children():
				if c is CollisionShape3D:
					shape = c.shape
					break
			if shape is ConcavePolygonShape3D or shape is HeightMapShape3D:
				kind = "step_sand" if water_level > -INF and pos.y < water_level + 1.0 else "step_grass"
			else:
				kind = "step_wood"  # suelos de interiores, muelle, tablas
	at(body, kind, pos + Vector3(0, 0.05, 0), 0.18)


static func _play(parent: Node, key: String, stream: AudioStream = null, volume: float = -8.0, delay: float = 0.0) -> void:
	if not parent.is_inside_tree():
		return
	if not _cache.has(key):
		_cache[key] = stream if stream != null else _noise(NOISES[key])
	var p := AudioStreamPlayer.new()
	p.stream = _cache[key]
	p.volume_db = volume if NOISES.get(key, null) == null else NOISES[key][4]
	parent.add_child(p)
	p.finished.connect(p.queue_free)
	if delay > 0.0:
		parent.get_tree().create_timer(delay).timeout.connect(func(): if is_instance_valid(p): p.play())
	else:
		p.play()


static func _tone(notes: Array) -> AudioStreamWAV:
	var rate := 22050
	var per_note := int(rate * 0.14)
	var data := PackedByteArray()
	data.resize(per_note * notes.size() * 2)
	for n in notes.size():
		for i in per_note:
			var t := float(i) / rate
			var env := exp(-t * 18.0) * minf(1.0, i / 200.0)
			var v := sin(TAU * notes[n] * t) * 0.6 + sin(TAU * notes[n] * 2.0 * t) * 0.15
			data.encode_s16((n * per_note + i) * 2, int(clampf(v * env, -1.0, 1.0) * 32000.0))
	return _wav(data, rate)


## Ruido con envolvente: un filtro de un polo da el "brillo" y un seno grave opcional el cuerpo.
static func _noise(spec: Array) -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * float(spec[0]))
	var decay: float = spec[1]
	var bright: float = spec[2]
	var tone: float = spec[3]
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(spec)
	var lp := 0.0
	for i in n:
		var t := float(i) / rate
		var env := exp(-t * decay) * minf(1.0, i / 60.0)
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.05 + bright * 0.9)
		var v := lp * 0.8
		if tone > 0.0:
			v += sin(TAU * tone * t) * 0.6 * exp(-t * decay * 0.7)
		data.encode_s16(i * 2, int(clampf(v * env, -1.0, 1.0) * 30000.0))
	return _wav(data, rate)


static func _wav(data: PackedByteArray, rate: int) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.data = data
	return wav
