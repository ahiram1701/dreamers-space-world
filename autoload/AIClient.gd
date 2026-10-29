extends Node
## Cliente de Ollama Cloud. Todo el juego habla con la IA solo a través de chat(),
## así cambiar de proveedor (u Ollama local) no toca nada más.
##
## Uso:  var r := await AIClient.chat(messages, schema, "npc")
##       r = { ok: bool, data: Variant (JSON parseado), text: String, error: String }

const TIMEOUT_SEC := 90.0
const MAX_RETRIES := 2  # reintentos de red (no de validación; eso lo hace ContentGenerator)
const FALLBACK_DIR := "res://data/fallback/"


func chat(messages: Array, schema: Dictionary = {}, mock_type: String = "") -> Dictionary:
	if Settings.use_mock:
		return await _mock(mock_type)
	if not Settings.has_api_key():
		return _fail("Falta la API key de Ollama Cloud (Ajustes).")

	var body := {
		"model": Settings.model,
		"messages": messages,
		"stream": false,
		"options": {"temperature": 0.9},
	}
	if not schema.is_empty():
		body["format"] = schema  # Ollama restringe la salida a este JSON schema

	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer " + Settings.api_key,
	])

	var last_error := ""
	for attempt in MAX_RETRIES + 1:
		if attempt > 0:
			await get_tree().create_timer(1.5 * attempt).timeout
		var res := await _post(Settings.endpoint, headers, JSON.stringify(body))
		if res.ok:
			return res
		last_error = res.error
		if res.get("fatal", false):
			break
	return _fail(last_error)


func _post(url: String, headers: PackedStringArray, payload: String) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = TIMEOUT_SEC
	add_child(http)
	var err := http.request(url, headers, HTTPClient.METHOD_POST, payload)
	if err != OK:
		http.queue_free()
		return _fail("No se pudo iniciar la petición: %s" % error_string(err))

	var r: Array = await http.request_completed
	http.queue_free()
	var result: int = r[0]
	var code: int = r[1]
	var text: String = (r[3] as PackedByteArray).get_string_from_utf8()

	if result != HTTPRequest.RESULT_SUCCESS:
		return _fail("Error de red (%d)." % result)
	if code == 401 or code == 403:
		var f := _fail("API key inválida o sin permisos (HTTP %d)." % code)
		f["fatal"] = true
		return f
	if code == 404:
		var f := _fail("Modelo '%s' no encontrado (HTTP 404)." % Settings.model)
		f["fatal"] = true
		return f
	if code < 200 or code >= 300:
		return _fail("HTTP %d: %s" % [code, text.left(300)])

	var envelope = JSON.parse_string(text)
	if typeof(envelope) != TYPE_DICTIONARY or not envelope.has("message"):
		return _fail("Respuesta inesperada de Ollama.")
	var content: String = envelope["message"].get("content", "")
	return {"ok": true, "data": JSON.parse_string(content), "text": content, "error": ""}


func _mock(mock_type: String) -> Dictionary:
	await get_tree().create_timer(0.3).timeout  # simula latencia para que la UI se comporte igual
	var path := FALLBACK_DIR + mock_type + ".json"
	if mock_type.is_empty() or not FileAccess.file_exists(path):
		return _fail("Mock sin datos para '%s'." % mock_type)
	var text := FileAccess.get_file_as_string(path)
	return {"ok": true, "data": JSON.parse_string(text), "text": text, "error": ""}


func _fail(msg: String) -> Dictionary:
	return {"ok": false, "data": null, "text": "", "error": msg}
