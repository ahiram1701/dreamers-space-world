extends Node
## La ventana del juego: que quepa siempre en la pantalla (sin taparse con la barra de tareas),
## modos ventana / maximizada / pantalla completa (F11 o Alt+Enter), límite de FPS y VSync,
## y escala automática de la interfaz según el tamaño real de la pantalla.

const MODES := ["maximized", "fullscreen", "windowed"]
const FPS_OPTIONS := [30, 60, 120, 0]

var _last_size := Vector2i.ZERO


func _ready() -> void:
	apply()
	get_tree().root.size_changed.connect(_on_resized)
	Settings.changed.connect(apply)


## Aplica el modo de pantalla, los FPS y la escala de la interfaz (al arrancar y al guardar ajustes).
func apply() -> void:
	if DisplayServer.get_name() == "headless":
		return
	_ensure_fits.call_deferred()
	var mode: String = Settings.window_mode if Settings.window_mode in MODES else "maximized"
	match mode:
		"fullscreen":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		"windowed":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			fit_window()
		_:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	Engine.max_fps = Settings.max_fps
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if Settings.vsync else DisplayServer.VSYNC_DISABLED)
	_apply_ui_scale()


## En modo ventana: el 85 % de la zona útil (sin barra de tareas), centrada.
func fit_window() -> void:
	var screen := DisplayServer.window_get_current_screen()
	var usable := DisplayServer.screen_get_usable_rect(screen)
	var size := Vector2i(int(usable.size.x * 0.85), int(usable.size.y * 0.85))
	DisplayServer.window_set_size(size)
	DisplayServer.window_set_position(usable.position + (usable.size - size) / 2)


## Si por lo que sea la ventana queda más grande que la pantalla (Windows a veces la restaura sin
## maximizar), se ajusta a la zona útil.
func _ensure_fits() -> void:
	await get_tree().create_timer(0.6).timeout
	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
		return
	var usable := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	var size := DisplayServer.window_get_size()
	var pos := DisplayServer.window_get_position()
	if size.x > usable.size.x or size.y > usable.size.y or pos.y < usable.position.y or pos.y + size.y > usable.end.y:
		fit_window()


## F11 / Alt+Enter: pantalla completa o volver a la ventana maximizada.
func toggle_fullscreen() -> void:
	Settings.window_mode = "maximized" if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN else "fullscreen"
	Settings.save_settings()
	apply()


## Escala de la interfaz. La ventana ya escala todo el diseño (base 1210×680) a su tamaño, así que
## en "automático" (0) se deja en 1; el jugador puede agrandarla o reducirla en Ajustes.
func ui_scale() -> float:
	return clampf(Settings.ui_scale, 0.75, 1.4) if Settings.ui_scale > 0.0 else 1.0


func _apply_ui_scale() -> void:
	get_tree().root.content_scale_factor = ui_scale()


func _on_resized() -> void:
	var s := get_tree().root.size
	if s != _last_size:
		_last_size = s
		_apply_ui_scale()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("fullscreen") or (event is InputEventKey and event.pressed and not event.echo
			and event.keycode == KEY_ENTER and event.alt_pressed):
		toggle_fullscreen()
		get_viewport().set_input_as_handled()
