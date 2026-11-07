extends Node
## La música del juego (v0.8.0): pistas de verdad (CC0, ver assets/CREDITS.md) que cambian según
## dónde estés y qué pase, con un fundido de 3 s entre una y otra. Suena en todas las escenas:
## el menú, el pueblo de día y de noche, el campo, la cafetería, otros planetas, el espacio y
## los momentos de tensión (la nave con el casco destrozado). El volumen: Ajustes → Música.

const TRACKS := {
	"menu": ["menu.ogg"],
	"town_day": ["town_day.ogg", "town_day_2.mp3"],
	"town_night": ["town_night.ogg"],
	"countryside": ["countryside.ogg"],
	"cafe": ["cafe.mp3"],
	"planet": ["planet.ogg"],
	"space": ["space.ogg", "space_2.ogg"],
	"tension": ["tension.ogg"],
}
const DIR := "res://assets/music/"
const FADE := 3.0
## Cuánto suena respecto al volumen de Ajustes (la música va de fondo, no tapa las voces).
const LEVEL := 0.55

## Una escena puede forzar un ambiente ("" = el que toque solo).
var forced := ""

var _a: AudioStreamPlayer
var _b: AudioStreamPlayer
var _current := ""          # ambiente que suena
var _check := 0.0
var _streams := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # también en pausa
	_a = AudioStreamPlayer.new()
	_b = AudioStreamPlayer.new()
	for p in [_a, _b]:
		p.volume_db = -80.0
		add_child(p)


func current() -> String:
	return _current


## Al cerrar el juego: callar y soltar las pistas antes de que se desmonte todo (si no, el
## reproductor podía seguir mezclando audio a medio cerrar y el juego fallaba al salir).
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_EXIT_TREE or what == NOTIFICATION_PREDELETE:
		_shutdown()


func _shutdown() -> void:
	set_process(false)
	for p in [_a, _b]:
		if p and is_instance_valid(p):
			p.stop()
			p.stream = null
	_streams.clear()


func _process(delta: float) -> void:
	if not is_inside_tree() or get_tree() == null:
		return
	_check -= delta
	if _check <= 0.0:
		_check = 1.0
		var want := forced if not forced.is_empty() else _pick()
		if want != _current:
			_switch(want)
	# Fundido: la que entra sube, la otra baja hasta callarse
	var target := linear_to_db(maxf(Settings.music_volume * LEVEL, 0.0001)) if Settings.music_volume > 0.001 else -80.0
	var k := clampf(delta / FADE * 3.0, 0.0, 1.0)
	_a.volume_db = lerpf(_a.volume_db, target if _current != "" else -80.0, k)
	_b.volume_db = lerpf(_b.volume_db, -80.0, k)
	if _b.playing and _b.volume_db < -60.0:
		_b.stop()


func _switch(mood: String) -> void:
	_current = mood
	var stream := _stream_for(mood)
	# La que sonaba pasa a «saliendo»; la nueva entra desde silencio
	var old := _a
	_a = _b
	_b = old
	_a.stream = stream
	_a.volume_db = -60.0
	# Sin pantalla (pruebas, CI) el audio es de mentira: se elige la pista pero no suena (si no,
	# el servidor de audio la retenía al cerrar y Godot avisaba de recursos sin liberar)
	if stream and DisplayServer.get_name() != "headless":
		_a.play()


func _stream_for(mood: String) -> AudioStream:
	var list: Array = TRACKS.get(mood, [])
	if list.is_empty():
		return null
	var file: String = list[randi() % list.size()]
	if _streams.has(file):
		return _streams[file]
	var path := DIR + file
	if not ResourceLoader.exists(path):
		return null
	var s: AudioStream = load(path)
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = true
	elif s is AudioStreamMP3:
		(s as AudioStreamMP3).loop = true
	_streams[file] = s
	return s


## Qué toca según la escena y lo que pasa en ella.
func _pick() -> String:
	var scene := get_tree().current_scene
	if scene == null or not is_instance_valid(scene) or scene.is_queued_for_deletion() or not scene.is_inside_tree():
		return ""
	var path := str(scene.scene_file_path)
	if path.contains("main_menu") or path.contains("MainMenu"):
		return "menu"
	if path.contains("SpaceScene"):
		var ship: Variant = scene.get("ship")
		if ship and is_instance_valid(ship) and float(ship.get("hull")) < 25.0:
			return "tension"
		return "space"
	var interiors: Variant = scene.get("_interiors")
	if interiors and interiors.call("is_inside") and str(interiors.call("current_kind")) in ["cafe", "restaurant"]:
		return "cafe"
	if path.contains("GeneratedLocation"):
		return "planet"
	if path.contains("Act0Town"):
		var player: Variant = scene.get("_player")
		if player and is_instance_valid(player) and not interiors.call("is_inside"):
			var p: Vector3 = player.global_position
			if p.x < -115.0 or absf(p.z) > 135.0:
				return "countryside" if WorldClock.night() < 0.5 else "town_night"
		return "town_night" if WorldClock.night() > 0.5 else "town_day"
	if path.contains("Awakening") or path.contains("awakening"):
		return "town_night"
	return ""
