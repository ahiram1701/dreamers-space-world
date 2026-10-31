extends Node
## Busca versiones ESTABLES nuevas en GitHub Releases y actualiza el juego con un clic.
## Windows no deja sobrescribir un .exe en ejecución, pero sí renombrarlo: el actual pasa a
## *.old, el nuevo ocupa su sitio y el juego se relanza. Los mundos viven en user:// y no se tocan.
##
## Uso:  Updater.check()  →  state_changed(AVAILABLE)  →  Updater.download_and_install()

signal state_changed(state: State)
signal progress_changed(value: float)

enum State { IDLE, DISABLED, CHECKING, UP_TO_DATE, AVAILABLE, DOWNLOADING, VERIFYING, INSTALLING, ERROR }

# /releases/latest excluye pre-releases y borradores: es justo el canal "solo estables".
const API_LATEST := "https://api.github.com/repos/ahiram1701/dreamers-space-world/releases/latest"
const DOWNLOAD_DIR := "user://updates/"
const STAGING_DIR := ".update"
const OLD_SUFFIX := ".old"
const SUMS_ASSET := "SHA256SUMS.txt"

var state: State = State.IDLE
var latest_version := ""
var release_url := ""
var release_notes := ""
var error_message := ""
var progress := 0.0

var _asset_name := ""
var _asset_url := ""
var _sums_url := ""
var _download: HTTPRequest


func _ready() -> void:
	if _is_installed_build():
		_cleanup_previous_update()


func current_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0"))


## Solo una build exportada en una carpeta escribible puede reemplazarse a sí misma.
## En el resto de casos "Actualizar" abre la página de la Release.
func can_self_update() -> bool:
	return _is_installed_build() and _exe_dir_writable() and not _asset_url.is_empty()


func check() -> void:
	if state in [State.CHECKING, State.DOWNLOADING, State.VERIFYING, State.INSTALLING]:
		return
	if not _is_installed_build():
		_set_state(State.DISABLED)  # editor o CI: no hay nada que reemplazar
		return
	_set_state(State.CHECKING)

	var res := await _request(API_LATEST)
	if not res.ok:
		_fail(res.error)
		return
	var release = JSON.parse_string(res.body.get_string_from_utf8())
	if typeof(release) != TYPE_DICTIONARY or not release.has("tag_name"):
		_fail("Respuesta inesperada de GitHub.")
		return

	latest_version = str(release.tag_name).trim_prefix("v")
	release_url = release.get("html_url", "")
	release_notes = str(release.get("body", ""))
	if not SemVer.is_newer(latest_version, current_version()):
		_set_state(State.UP_TO_DATE)
		return

	_asset_name = ""
	_asset_url = ""
	_sums_url = ""
	var suffix := "-windows.zip" if OS.get_name() == "Windows" else "-linux.zip"
	for asset in release.get("assets", []):
		var asset_name: String = asset.get("name", "")
		if asset_name.ends_with(suffix):
			_asset_name = asset_name
			_asset_url = asset.get("browser_download_url", "")
		elif asset_name == SUMS_ASSET:
			_sums_url = asset.get("browser_download_url", "")
	_set_state(State.AVAILABLE)


## true si ya se encontró una versión nueva (sigue siendo cierto si la descarga falló: se puede reintentar).
func has_update() -> bool:
	return not latest_version.is_empty() and SemVer.is_newer(latest_version, current_version())


func download_and_install() -> void:
	if not (state == State.AVAILABLE or (state == State.ERROR and has_update())):
		return
	if not can_self_update() or _sums_url.is_empty():
		OS.shell_open(release_url)  # actualización manual desde la página de la Release
		return

	_set_state(State.DOWNLOADING)
	DirAccess.make_dir_recursive_absolute(DOWNLOAD_DIR)
	var zip_path := DOWNLOAD_DIR + _asset_name
	var res := await _request(_asset_url, zip_path)
	if not res.ok:
		_fail(res.error)
		return

	_set_state(State.VERIFYING)
	var sums := await _request(_sums_url)
	var expected := _expected_sha256(sums.body.get_string_from_utf8() if sums.ok else "", _asset_name)
	if expected.is_empty() or FileAccess.get_sha256(zip_path) != expected:
		DirAccess.remove_absolute(zip_path)
		_fail("La descarga no pasó la verificación SHA-256. Inténtalo de nuevo.")
		return

	_set_state(State.INSTALLING)
	var installed := _install(zip_path)
	if not installed.ok:
		_fail(installed.error)
		return
	DirAccess.remove_absolute(zip_path)
	OS.create_process(installed.executable, [])
	WorldDB.flush()  # nada pendiente sin guardar antes de reiniciar
	get_tree().quit()


func _process(_delta: float) -> void:
	if _download == null:
		return
	var total := _download.get_body_size()
	if total > 0:
		progress = float(_download.get_downloaded_bytes()) / total
		progress_changed.emit(progress)


# --- Instalación --------------------------------------------------------------------

## Extrae el zip a una carpeta temporal junto al exe y luego intercambia archivo por archivo,
## guardando los actuales como *.old para poder deshacer si algo falla a mitad.
func _install(zip_path: String) -> Dictionary:
	var exe_dir := OS.get_executable_path().get_base_dir()
	var staging := exe_dir.path_join(STAGING_DIR)
	var reader := ZIPReader.new()
	if reader.open(ProjectSettings.globalize_path(zip_path)) != OK:
		return {"ok": false, "error": "No se pudo abrir la actualización."}

	var files: Array[String] = []
	for f in reader.get_files():
		if f.ends_with("/") or f.begins_with("/") or ".." in f:
			continue  # carpetas y rutas que se saldrían de la carpeta del juego
		files.append(f)
		var out := staging.path_join(f)
		DirAccess.make_dir_recursive_absolute(out.get_base_dir())
		var fa := FileAccess.open(out, FileAccess.WRITE)
		if fa == null:
			reader.close()
			return {"ok": false, "error": "No se pudo escribir %s." % out}
		fa.store_buffer(reader.read_file(f))
		fa.close()
	reader.close()

	var executable := OS.get_executable_path()
	var swapped: Array[String] = []
	for f in files:
		var target := exe_dir.path_join(f)
		DirAccess.make_dir_recursive_absolute(target.get_base_dir())
		if FileAccess.file_exists(target):
			DirAccess.remove_absolute(target + OLD_SUFFIX)
			if DirAccess.rename_absolute(target, target + OLD_SUFFIX) != OK:
				_rollback(swapped)
				return {"ok": false, "error": "No se pudo reemplazar %s." % f}
		if DirAccess.rename_absolute(staging.path_join(f), target) != OK:
			DirAccess.rename_absolute(target + OLD_SUFFIX, target)
			_rollback(swapped)
			return {"ok": false, "error": "No se pudo instalar %s." % f}
		swapped.append(target)
		if f.ends_with(".exe") or f.ends_with(".x86_64"):
			if OS.get_name() == "Linux":
				OS.execute("chmod", ["+x", target])
			if not f.ends_with(".console.exe"):  # el wrapper de consola de Godot no es el juego
				executable = target  # relanzar el exe nuevo aunque el actual tenga otro nombre
	_remove_dir_recursive(staging)
	return {"ok": true, "executable": executable}


func _rollback(swapped: Array[String]) -> void:
	for target in swapped:
		DirAccess.remove_absolute(target)
		DirAccess.rename_absolute(target + OLD_SUFFIX, target)


## Tras reiniciar: borra los *.old y las descargas de la actualización anterior.
## Si el proceso viejo aún no ha soltado el .exe, se reintenta en el siguiente arranque.
func _cleanup_previous_update() -> void:
	var exe_dir := OS.get_executable_path().get_base_dir()
	var dir := DirAccess.open(exe_dir)
	if dir:
		for f in dir.get_files():
			if f.ends_with(OLD_SUFFIX):
				DirAccess.remove_absolute(exe_dir.path_join(f))
	_remove_dir_recursive(exe_dir.path_join(STAGING_DIR))
	_remove_dir_recursive(ProjectSettings.globalize_path(DOWNLOAD_DIR))


func _remove_dir_recursive(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for f in dir.get_files():
		DirAccess.remove_absolute(path.path_join(f))
	for d in dir.get_directories():
		_remove_dir_recursive(path.path_join(d))
	DirAccess.remove_absolute(path)


# --- Utilidades ---------------------------------------------------------------------

## GET con cabeceras de GitHub. Con `to_file` descarga a disco (sigue redirecciones al CDN).
func _request(url: String, to_file: String = "") -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = 600.0 if not to_file.is_empty() else 20.0
	http.download_file = to_file
	add_child(http)
	if not to_file.is_empty():
		_download = http
	var headers := PackedStringArray([
		"User-Agent: DreamersSpaceWorld/" + current_version(),
		"Accept: application/vnd.github+json",
	])
	var err := http.request(url, headers)
	if err != OK:
		http.queue_free()
		return {"ok": false, "error": "No se pudo conectar (%s)." % error_string(err), "body": PackedByteArray()}
	var r: Array = await http.request_completed
	_download = null
	http.queue_free()
	if r[0] != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "error": "Sin conexión con GitHub (%d)." % r[0], "body": PackedByteArray()}
	if r[1] < 200 or r[1] >= 300:
		return {"ok": false, "error": "GitHub respondió HTTP %d." % r[1], "body": PackedByteArray()}
	return {"ok": true, "error": "", "body": r[3]}


## Formato de `sha256sum`: "<hash>  <archivo>" por línea.
func _expected_sha256(sums: String, file_name: String) -> String:
	for line in sums.split("\n", false):
		var parts := line.strip_edges().split(" ", false)
		if parts.size() == 2 and parts[1].trim_prefix("*") == file_name:
			return parts[0].to_lower()
	return ""


func _is_installed_build() -> bool:
	return OS.has_feature("template") and not OS.has_feature("editor")


func _exe_dir_writable() -> bool:
	var probe := OS.get_executable_path().get_base_dir().path_join(".write_test")
	var f := FileAccess.open(probe, FileAccess.WRITE)
	if f == null:
		return false
	f.close()
	DirAccess.remove_absolute(probe)
	return true


func _set_state(s: State) -> void:
	state = s
	state_changed.emit(s)


func _fail(msg: String) -> void:
	error_message = msg
	push_warning("Updater: " + msg)
	_set_state(State.ERROR)
