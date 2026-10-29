class_name Sfx
extends RefCounted
## Efectos de sonido sintetizados (el juego no lleva archivos de audio).

static var _cache := {}


## Dos notas cortas y brillantes: "has recibido algo".
static func chime(parent: Node) -> void:
	_play(parent, "chime", [880.0, 1318.5])


## Una nota grave: "algo no ha salido".
static func deny(parent: Node) -> void:
	_play(parent, "deny", [220.0])


static func _play(parent: Node, key: String, notes: Array) -> void:
	if not _cache.has(key):
		_cache[key] = _tone(notes)
	var p := AudioStreamPlayer.new()
	p.stream = _cache[key]
	p.volume_db = -8.0
	parent.add_child(p)
	p.finished.connect(p.queue_free)
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
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.data = data
	return wav
