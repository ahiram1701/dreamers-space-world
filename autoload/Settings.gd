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


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("ai", "api_key", api_key)
	cfg.set_value("ai", "model", model)
	cfg.set_value("ai", "endpoint", endpoint)
	cfg.set_value("ai", "use_mock", use_mock)
	cfg.set_value("game", "language", language)
	var err := cfg.save_encrypted_pass(PATH, _passphrase())
	if err != OK:
		push_error("No se pudieron guardar los ajustes: %s" % error_string(err))
	changed.emit()


# Atado a la máquina: copiar settings.cfg a otro PC no expone la key.
func _passphrase() -> String:
	return ("dsw-" + OS.get_unique_id()).sha256_text()
