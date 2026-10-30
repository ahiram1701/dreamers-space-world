class_name ActionPanel
extends CanvasLayer
## "Hacer algo" (tecla F): el jugador escribe lo que hace ("le doy la radio a Samir", "talo el
## árbol de al lado y hago una balsa") y lo ve pasar: la IA lo convierte en pasos
## (StoryDirector.act) y el ActionPerformer los representa uno a uno, con subtítulos.
## Mientras ocurre, el jugador puede moverse para cancelar lo que queda.

signal opened
signal closed

## Devuelve la descripción de dónde está el jugador y qué tiene cerca. Lo asigna la escena.
var context: Callable = func(): return ""
## El personaje que hace la acción (para verle hacerla).
var player: Player
## Representa los pasos (lo asigna la escena común, LocationScene).
var performer: ActionPerformer
## Ideas según lo que hay cerca y cómo estás (LocationScene.suggestions). Sin IA.
var suggestions: Callable = func(): return []

const EXAMPLES := ["Talo el árbol de al lado y hago una balsa", "Le pido un café a Teo y se lo pago",
	"Me siento en el banco a mirar el mar", "Llamo a un fontanero para arreglar la cocina", "Busco algo útil entre las redes del muelle",
	"Le doy un abrazo a Marina", "Abro una panadería en el solar vacío", "Me ducho y me cambio de ropa"]

## Palabras → gesto que empieza nada más pulsar "Hacer", mientras la IA decide qué pasa.
const GUESS := [
	[["talo", "talar", "tala ", "corto", "cortar", "hacha", "leña"], "chop"], [["constru", "arregl", "repar", "clav", "martill", "fabric", "monto", "ato"], "hammer"],
	[["cav", "excav", "entierr", "pala", "plant"], "dig"], [["busc", "rebusc", "registr", "examin", "inspeccion", "rastre"], "search"],
	[["recoj", "recog", "cojo", "agarr", "levant", "tomo "], "pick_up"], [["siento", "sentar", "descans"], "sit"],
	[["duerm", "dormir", "tumb", "acuest"], "sleep"], [["bebo", "beber", "trago"], "drink"], [["comer", "me como", "como algo", "almuerz", "ceno", "desayun"], "eat"],
	[["pego", "golpe", "puñetazo", "pegar"], "punch"], [["empuj"], "push"], [["pate", "patada"], "kick"], [["abraz"], "hug"],
	[["doy la mano", "estrecho la mano"], "handshake"], [["salud"], "wave"], [["señal", "apunt"], "point"], [["pesc", "caña"], "fish"],
	[["nad"], "swim"], [["bail"], "dance"], [["lanz", "tiro "], "throw"], [["escrib", "anoto"], "write"], [["leo ", "leer"], "read"],
	[["escucho", "escuchar"], "listen"], [["llamo", "llamar"], "call"], [["arrodill"], "kneel"],
	[["piens", "pensar", "medit", "reflexion"], "think"], [["agach", "escond"], "crouch"],
]

var _bar: PanelContainer
var _input: LineEdit
var _go: Button
var _subtitle: PanelContainer
var _subtitle_text: RichTextLabel
var _busy := false
var _open := false
var _chips: HFlowContainer
var _history: Array = []
var _history_i := -1


func _ready() -> void:
	layer = 12
	# Barra de entrada abajo, estrecha: se ve al personaje
	_bar = PanelContainer.new()
	_bar.anchor_left = 0.18
	_bar.anchor_right = 0.82
	_bar.anchor_top = 1.0
	_bar.anchor_bottom = 1.0
	_bar.offset_top = -126
	_bar.offset_bottom = -18
	_bar.visible = false
	UIStyle.apply(_bar)
	add_child(_bar)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	_bar.add_child(col)
	_chips = HFlowContainer.new()  # ideas: un clic y se copian al campo para editarlas
	_chips.add_theme_constant_override("h_separation", 6)
	col.add_child(_chips)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)
	var title := Label.new()
	title.text = "¿Qué haces?"
	title.add_theme_font_size_override("font_size", 18)
	row.add_child(title)
	_input = LineEdit.new()
	_input.placeholder_text = "Por ejemplo: talo el árbol de al lado · le doy la radio a Samir · me siento en el banco"
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.text_submitted.connect(func(_t): _do())
	_input.gui_input.connect(_on_input_key)
	row.add_child(_input)
	_go = Button.new()
	_go.text = "Hacer"
	_go.pressed.connect(_do)
	row.add_child(_go)
	var close_btn := Button.new()
	close_btn.text = "Cerrar"
	close_btn.pressed.connect(close)
	row.add_child(close_btn)

	# Subtítulos de lo que va pasando (no bloquean: moverse cancela)
	_subtitle = PanelContainer.new()
	_subtitle.anchor_left = 0.15
	_subtitle.anchor_right = 0.85
	_subtitle.anchor_top = 1.0
	_subtitle.anchor_bottom = 1.0
	_subtitle.offset_top = -150
	_subtitle.offset_bottom = -60
	_subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_subtitle.modulate.a = 0.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.05, 0.09, 0.62)
	style.set_corner_radius_all(10)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	_subtitle.add_theme_stylebox_override("panel", style)
	add_child(_subtitle)
	_subtitle_text = RichTextLabel.new()
	_subtitle_text.bbcode_enabled = true
	_subtitle_text.fit_content = true
	_subtitle_text.scroll_active = false
	_subtitle_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_subtitle_text.add_theme_font_size_override("normal_font_size", 19)
	_subtitle.add_child(_subtitle_text)


func is_open() -> bool:
	return _open


func is_busy() -> bool:
	return _busy


func open(prefill: String = "") -> void:
	if _busy:
		return
	_open = true
	_input.editable = true
	_input.text = prefill
	_input.caret_column = prefill.length()
	_input.placeholder_text = "Por ejemplo: " + EXAMPLES[randi() % EXAMPLES.size()].to_lower()
	_history_i = -1
	_fill_chips()
	UIAnim.show(_bar, Vector2(0, 12))
	opened.emit()
	_input.grab_focus.call_deferred()


func _fill_chips() -> void:
	for c in _chips.get_children():
		c.queue_free()
	var ideas: Array = suggestions.call() if suggestions.is_valid() else []
	_chips.visible = not ideas.is_empty()
	for idea in ideas.slice(0, 5):
		var b := Button.new()
		b.text = idea
		b.add_theme_font_size_override("font_size", 14)
		var sb := UITheme.box(Color(UITheme.ACCENT, 0.1), Color(UITheme.ACCENT, 0.3), 14, 6)
		sb.content_margin_left = 12
		sb.content_margin_right = 12
		b.add_theme_stylebox_override("normal", sb)
		b.pressed.connect(func():
			_input.text = idea
			_input.caret_column = idea.length()
			_input.grab_focus())
		_chips.add_child(b)


## ↑ y ↓ recuperan lo que escribiste antes.
func _on_input_key(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed) or _history.is_empty():
		return
	if e.keycode == KEY_UP:
		_history_i = mini(_history_i + 1, _history.size() - 1)
	elif e.keycode == KEY_DOWN:
		_history_i = maxi(_history_i - 1, -1)
	else:
		return
	_input.text = _history[_history.size() - 1 - _history_i] if _history_i >= 0 else ""
	_input.caret_column = _input.text.length()
	_input.accept_event()


func close() -> void:
	if not _open:
		return
	_open = false
	UIAnim.hide(_bar)
	closed.emit()


static func guess_gesture(text: String) -> String:
	var t := " " + text.to_lower()
	for entry in GUESS:
		for k in entry[0]:
			if t.contains(" " + k):
				return entry[1]
	return ""


func _do() -> void:
	var what := _input.text.strip_edges()
	if what.is_empty() or _busy:
		return
	_busy = true
	_input.clear()
	_history.append(what)
	if _history.size() > 30:
		_history.pop_front()
	close()  # el jugador vuelve a ver (y puede cancelar moviéndose)
	_show("[color=#8fb3ff][i]%s[/i][/color]   [color=gray]…[/color]" % what)
	var guess := guess_gesture(what)
	if player and guess in ["think", "search"]:
		player.play_gesture(guess, 30.0)  # mientras decide, ya se le ve hacer algo
	var r := await StoryDirector.act(what, context.call())
	if player and guess in ["think", "search"]:
		player.stop_gesture()
	var steps: Array = r.get("steps", [])
	var notes := []
	if not r.ok:
		_show("[color=#f2a65a]Lo intentas, pero no pasa nada especial. (Sin respuesta de la IA: %s)[/color]" % r.error.replace("[", "(").replace("]", ")"))
		Sfx.deny(self)
		if performer:
			await performer.perform(ActionPerformer.local_plan(what, performer.scene, guess))
	else:
		_show(r.narration)
		if performer and not steps.is_empty():
			notes = await performer.perform(steps, func(text): _show(text))
		else:
			notes = Actions.execute("", steps)
		WorldClock.advance(r.get("minutes", 0))
		if not notes.is_empty():
			_show("%s\n[color=#7ee08a]» %s[/color]" % [r.narration, "\n» ".join(PackedStringArray(notes))])
			Sfx.chime(self)
		else:
			_show(r.narration)
	_busy = false
	await get_tree().create_timer(clampf(_subtitle_text.get_parsed_text().length() * 0.06, 4.0, 10.0)).timeout
	if not _busy:
		var tw := create_tween()
		tw.tween_property(_subtitle, "modulate:a", 0.0, 0.8)


func _show(text: String) -> void:
	_subtitle_text.text = text
	_subtitle.modulate.a = 1.0
