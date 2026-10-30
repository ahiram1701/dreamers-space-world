extends Node
## Ajustes del jugador. La API key se guarda cifrada en user://, nunca en res://.

signal changed

const PATH := "user://settings.cfg"
const DEFAULT_MODEL := "gpt-oss:120b"
const DEFAULT_ENDPOINT := "https://ollama.com/api/chat"

var api_key: String = ""
var model: String = DEFAULT_MODEL
var endpoint: String = DEFAULT_ENDPOINT
var language: String = "es"
## Sin red ni coste: AIClient responde con los JSON de res://data/fallback/.
var use_mock: bool = false
var auto_check_updates: bool = true
var mouse_sensitivity: float = 1.0  # multiplicador
var volume: float = 0.8             # 0..1, volumen general
var music_volume: float = 0.6       # 0..1, la música de fondo (0 = sin música)
## 0 baja, 1 media, 2 alta (lo aplica EnvironmentFX al entrar en cada escena).
var graphics_quality: int = 1
## Minutos reales que dura un día de juego (1440 = tiempo real).
var day_minutes: float = 120.0
## Aspecto del protagonista: "masculine", "feminine" o "" (lo decide el mundo).
var player_figure: String = ""
## Cámara: campo de visión (grados), invertir el eje vertical y distancia preferida.
var fov: float = 70.0
var invert_y: bool = false
var camera_distance: float = 4.0
## Interfaz: escala general, tamaño del texto y velocidad a la que aparecen las frases (1 = normal).
var ui_scale: float = 1.0
var text_scale: float = 1.0
var text_speed: float = 1.0
## Consejos de primera vez que ya se han visto (no se repiten).
var seen_hints: Array = []


func _ready() -> void:
	load_settings()


func has_api_key() -> bool:
	return not api_key.strip_edges().is_empty()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load_encrypted_pass(PATH, _passphrase()) != OK:
		return
	api_key = cfg.get_value("ai", "api_key", "")
	model = cfg.get_value("ai", "model", DEFAULT_MODEL)
	endpoint = cfg.get_value("ai", "endpoint", DEFAULT_ENDPOINT)
	use_mock = cfg.get_value("ai", "use_mock", false)
	language = cfg.get_value("game", "language", "es")
	auto_check_updates = cfg.get_value("game", "auto_check_updates", true)
	mouse_sensitivity = cfg.get_value("game", "mouse_sensitivity", 1.0)
	volume = cfg.get_value("game", "volume", 0.8)
	music_volume = cfg.get_value("game", "music_volume", 0.6)
	graphics_quality = cfg.get_value("game", "graphics_quality", 1)
	player_figure = cfg.get_value("game", "player_figure", "")
	day_minutes = cfg.get_value("game", "day_minutes", 120.0)
	fov = cfg.get_value("game", "fov", 70.0)
	invert_y = cfg.get_value("game", "invert_y", false)
	camera_distance = cfg.get_value("game", "camera_distance", 4.0)
	ui_scale = cfg.get_value("game", "ui_scale", 1.0)
	text_scale = cfg.get_value("game", "text_scale", 1.0)
	text_speed = cfg.get_value("game", "text_speed", 1.0)
	seen_hints = cfg.get_value("game", "seen_hints", [])
	_apply_volume()


func save_settings() -> void:
	# Pruebas y capturas automáticas no tocan los ajustes reales del jugador
	if DisplayServer.get_name() == "headless" or not OS.get_environment("DSW_NO_SAVE_SETTINGS").is_empty():
		changed.emit()
		return
	var cfg := ConfigFile.new()
	cfg.set_value("ai", "api_key", api_key)
	cfg.set_value("ai", "model", model)
	cfg.set_value("ai", "endpoint", endpoint)
	cfg.set_value("ai", "use_mock", use_mock)
	cfg.set_value("game", "language", language)
	cfg.set_value("game", "auto_check_updates", auto_check_updates)
	cfg.set_value("game", "mouse_sensitivity", mouse_sensitivity)
	cfg.set_value("game", "volume", volume)
	cfg.set_value("game", "music_volume", music_volume)
	cfg.set_value("game", "graphics_quality", graphics_quality)
	cfg.set_value("game", "player_figure", player_figure)
	cfg.set_value("game", "day_minutes", day_minutes)
	cfg.set_value("game", "fov", fov)
	cfg.set_value("game", "invert_y", invert_y)
	cfg.set_value("game", "camera_distance", camera_distance)
	cfg.set_value("game", "ui_scale", ui_scale)
	cfg.set_value("game", "text_scale", text_scale)
	cfg.set_value("game", "text_speed", text_speed)
	cfg.set_value("game", "seen_hints", seen_hints)
	_apply_volume()
	var err := cfg.save_encrypted_pass(PATH, _passphrase())
	if err != OK:
		push_error("No se pudieron guardar los ajustes: %s" % error_string(err))
	changed.emit()


func _apply_volume() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 0.0001)))


# Atado a la máquina: copiar settings.cfg a otro PC no expone la key.
func _passphrase() -> String:
	return ("dsw-" + OS.get_unique_id()).sha256_text()
