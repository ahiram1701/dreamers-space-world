extends Node
## Acciones de control (InputMap) con teclado + ratón y mando. Se registran al arrancar para
## que todo el juego use nombres ("interact", "act"…) en vez de teclas sueltas.

const KEYS := {
	"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
	"run": [KEY_SHIFT], "jump": [KEY_SPACE], "interact": [KEY_E], "act": [KEY_F],
	"inventory": [KEY_I], "anchor": [KEY_T], "pause": [KEY_ESCAPE], "phone": [KEY_C],
	"choice_1": [KEY_1], "choice_2": [KEY_2], "choice_3": [KEY_3], "choice_4": [KEY_4],
}
const BUTTONS := {
	"jump": [JOY_BUTTON_A], "interact": [JOY_BUTTON_X], "act": [JOY_BUTTON_Y],
	"inventory": [JOY_BUTTON_BACK], "anchor": [JOY_BUTTON_LEFT_SHOULDER], "pause": [JOY_BUTTON_START],
	"run": [JOY_BUTTON_LEFT_STICK], "phone": [JOY_BUTTON_RIGHT_SHOULDER], "zoom_in": [JOY_BUTTON_DPAD_UP], "zoom_out": [JOY_BUTTON_DPAD_DOWN],
}
const AXES := {
	"move_forward": [JOY_AXIS_LEFT_Y, -1.0], "move_back": [JOY_AXIS_LEFT_Y, 1.0],
	"move_left": [JOY_AXIS_LEFT_X, -1.0], "move_right": [JOY_AXIS_LEFT_X, 1.0],
	"look_up": [JOY_AXIS_RIGHT_Y, -1.0], "look_down": [JOY_AXIS_RIGHT_Y, 1.0],
	"look_left": [JOY_AXIS_RIGHT_X, -1.0], "look_right": [JOY_AXIS_RIGHT_X, 1.0],
}


func _ready() -> void:
	for action in KEYS:
		_ensure(action)
		for k in KEYS[action]:
			var e := InputEventKey.new()
			e.physical_keycode = k
			InputMap.action_add_event(action, e)
	for action in ["zoom_in", "zoom_out"]:
		_ensure(action)
		var w := InputEventMouseButton.new()
		w.button_index = MOUSE_BUTTON_WHEEL_UP if action == "zoom_in" else MOUSE_BUTTON_WHEEL_DOWN
		InputMap.action_add_event(action, w)
	for action in BUTTONS:
		_ensure(action)
		for b in BUTTONS[action]:
			var e := InputEventJoypadButton.new()
			e.button_index = b
			InputMap.action_add_event(action, e)
	for action in AXES:
		_ensure(action)
		var e := InputEventJoypadMotion.new()
		e.axis = AXES[action][0]
		e.axis_value = AXES[action][1]
		InputMap.action_add_event(action, e)


## true si lo último que se tocó fue un mando (los avisos muestran sus botones).
var using_gamepad := false


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.4):
		using_gamepad = true
	elif event is InputEventKey or event is InputEventMouseButton:
		using_gamepad = false


## Cómo se llama el control de una acción para mostrarlo ("E", "F", "X"…).
func label_for(action: String) -> String:
	if using_gamepad and BUTTONS.has(action):
		return {JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y", JOY_BUTTON_BACK: "Back",
			JOY_BUTTON_START: "Start", JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB", JOY_BUTTON_LEFT_STICK: "L3",
			JOY_BUTTON_DPAD_UP: "↑", JOY_BUTTON_DPAD_DOWN: "↓"}.get(BUTTONS[action][0], "?")
	if KEYS.has(action):
		return OS.get_keycode_string(KEYS[action][0]).replace("Escape", "Esc").replace("Space", "Espacio")
	return {"zoom_in": "Rueda", "zoom_out": "Rueda"}.get(action, action)


func _ensure(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.25)


## Dirección de movimiento (x: derecha, y: atrás), con el stick analógico o las teclas.
func move_vector() -> Vector2:
	return Input.get_vector("move_left", "move_right", "move_forward", "move_back")


## Giro de cámara con el stick derecho (por segundo).
func look_vector() -> Vector2:
	return Input.get_vector("look_left", "look_right", "look_up", "look_down")
