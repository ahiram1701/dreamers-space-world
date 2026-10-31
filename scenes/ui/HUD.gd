class_name HUD
extends CanvasLayer
## La información en pantalla durante el juego, mínima y que se aparta sola:
##   arriba a la izquierda  lugar, objetivo y misión (se desvanecen y vuelven al cambiar)
##   arriba a la derecha    día, hora, tiempo y dinero; debajo, las notificaciones
##   abajo a la izquierda   salud/energía/inestabilidad y necesidades, solo cuando importan
## Nada de listas de controles: eso está en la pausa (y en los consejos de la primera vez).

const FADE_AFTER := 8.0
const SHOW_WHEN_BELOW := 40.0
const RECENT := 6.0
const KIND_COLOR := {"info": Color("#73d9ff"), "item": Color("#7ee08a"), "money": Color("#ffd27a"), "quest": Color("#f2c14e"),
	"memory": Color("#c9a7ff"), "warn": Color("#ef6b6b")}

var _place: Label
var _objective: Label
var _tracker: Label
var _top_left: VBoxContainer
var _top_left_t := 0.0
var _clock: Label
var _weather: Label
var _money: Label
var _notes: VBoxContainer
var _vitals: VBoxContainer
var _rows := {}         # stat/necesidad -> {row, bar, t}
var _tick := 0.0
## El jugador (para la flecha del destino marcado en el mapa).
var player: Player
var _waypoint := Vector3.INF
var _waypoint_label := ""
var _arrow: Label
var _vignette: ColorRect
var _fps: Label


func _ready() -> void:
	layer = 5
	add_to_group("hud")
	# Viñeta de cansancio (bordes oscuros cuando te caes de sueño)
	_vignette = ColorRect.new()
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vm := ShaderMaterial.new()
	vm.shader = preload("res://shaders/vignette.gdshader")
	_vignette.material = vm
	_vignette.modulate.a = 0.0
	add_child(_vignette)
	_fps = Label.new()  # contador de FPS (Ajustes → Imagen)
	_fps.anchor_left = 1.0
	_fps.anchor_right = 1.0
	_fps.anchor_top = 1.0
	_fps.anchor_bottom = 1.0
	_fps.offset_left = -90
	_fps.offset_top = -30
	_fps.add_theme_font_size_override("font_size", 13)
	_fps.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	add_child(_fps)
	# Flecha hacia el destino marcado en el mapa
	_arrow = Label.new()
	_arrow.anchor_left = 0.5
	_arrow.anchor_right = 0.5
	_arrow.offset_top = 16
	_arrow.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_arrow.add_theme_font_size_override("font_size", 17)
	_arrow.add_theme_color_override("font_color", Color("#ffd27a"))
	_arrow.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_arrow.add_theme_constant_override("shadow_outline_size", 4)
	_arrow.visible = false
	add_child(_arrow)
	# Arriba a la izquierda
	_top_left = VBoxContainer.new()
	_top_left.position = Vector2(24, 18)
	_top_left.add_theme_constant_override("separation", 2)
	add_child(_top_left)
	_place = _label(_top_left, 15, UITheme.MUTED)
	_objective = _label(_top_left, 21, UITheme.TEXT)
	_objective.add_theme_font_override("font", UITheme.font_bold)
	_tracker = _label(_top_left, 15, Color("#ffd9a0"))

	# Arriba a la derecha
	var right := VBoxContainer.new()
	right.anchor_left = 1.0
	right.anchor_right = 1.0
	right.offset_left = -330
	right.offset_right = -22
	right.offset_top = 16
	right.add_theme_constant_override("separation", 10)
	add_child(right)
	var info := HBoxContainer.new()
	info.alignment = BoxContainer.ALIGNMENT_END
	info.add_theme_constant_override("separation", 14)
	right.add_child(info)
	_weather = _label(info, 15, UITheme.MUTED)
	_money = _label(info, 16, UITheme.MONEY)
	_clock = _label(info, 17, UITheme.TEXT)
	_clock.add_theme_font_override("font", UITheme.font_bold)
	_notes = VBoxContainer.new()
	_notes.add_theme_constant_override("separation", 8)
	right.add_child(_notes)

	# Abajo a la izquierda
	_vitals = VBoxContainer.new()
	_vitals.anchor_top = 1.0
	_vitals.anchor_bottom = 1.0
	_vitals.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_vitals.offset_left = 24
	_vitals.offset_bottom = -22
	_vitals.add_theme_constant_override("separation", 6)
	add_child(_vitals)
	for s in [["health", "Salud", UITheme.DANGER], ["energy", "Ancla", UITheme.ACCENT], ["instability", "Inestabilidad", Color("#c77dff")],
			["hunger", "Hambre", Color("#e7a35b")], ["thirst", "Sed", Color("#5fb8e8")], ["rest", "Descanso", Color("#a5b4fc")],
			["hygiene", "Higiene", Color("#8fd6b4")]]:
		_add_row(s[0], s[1], s[2])

	GameState.stat_changed.connect(func(stat, _v): _touch(stat))
	Body.need_changed.connect(func(n, _v): _touch(n))
	Wallet.changed.connect(_on_money)
	_refresh(true)


func _label(parent: Node, size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.add_theme_constant_override("shadow_outline_size", 4)
	parent.add_child(l)
	return l


func _add_row(key: String, text: String, color: Color) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.modulate.a = 0.0
	row.visible = false
	_vitals.add_child(row)
	var name := _label(row, 13, UITheme.MUTED)
	name.text = text
	name.custom_minimum_size.x = 92
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(150, 8)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.show_percentage = false
	bar.max_value = 100
	bar.add_theme_stylebox_override("fill", UITheme.box(color, Color(0, 0, 0, 0), 4, 0))
	row.add_child(bar)
	_rows[key] = {"row": row, "bar": bar, "t": -INF}


# --- API ------------------------------------------------------------------------------

func set_place(text: String) -> void:
	if _place.text != text:
		_place.text = text
		_wake_top_left()


func set_objective(text: String) -> void:
	if _objective.text != text:
		_objective.text = text
		_wake_top_left()


func set_tracker(text: String) -> void:
	if _tracker.text != text:
		_tracker.text = text
		_tracker.visible = not text.is_empty()
		_wake_top_left()


## Una tarjeta de aviso (objeto, dinero, encargo, recuerdo…). Como mucho tres a la vez.
func notify(text: String, kind: String = "info") -> void:
	if text.strip_edges().is_empty():
		return
	Journal.log_event(text, kind)
	while _notes.get_child_count() >= 3:
		var old := _notes.get_child(0)
		_notes.remove_child(old)
		old.queue_free()
	var card := PanelContainer.new()
	var style := UITheme.box(UITheme.BG, Color(0, 0, 0, 0), 10, 12)
	style.border_color = KIND_COLOR.get(kind, UITheme.ACCENT)
	style.border_width_left = 4
	card.add_theme_stylebox_override("panel", style)
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 280
	l.add_theme_font_size_override("font_size", 15)
	card.add_child(l)
	_notes.add_child(card)
	UIAnim.show(card, Vector2(24, 0))
	var life := clampf(text.length() * 0.06, 3.5, 8.0)
	var tw := card.create_tween()
	tw.tween_interval(life)
	tw.tween_property(card, "modulate:a", 0.0, 0.6)
	tw.tween_callback(card.queue_free)


## Destino marcado en el mapa del celular ("" para quitarlo).
func set_waypoint(label: String, pos: Vector3) -> void:
	_waypoint_label = label
	_waypoint = pos
	_arrow.visible = not label.is_empty()


func _update_waypoint() -> void:
	if _waypoint == Vector3.INF or player == null:
		return
	var to := _waypoint - player.global_position
	to.y = 0
	var dist := to.length()
	if dist < 6.0:
		notify("Has llegado: %s" % _waypoint_label, "info")
		set_waypoint("", Vector3.INF)
		return
	var fwd := player.view_forward()
	var ang := rad_to_deg(fwd.signed_angle_to(to.normalized(), Vector3.UP))
	var arrows := ["↑", "↖", "←", "↙", "↓", "↘", "→", "↗"]
	var i := posmod(roundi(ang / 45.0), 8)
	_arrow.text = "%s  %s · %d m" % [arrows[i], _waypoint_label, roundi(dist)]


func _wake_top_left() -> void:
	_top_left_t = 0.0
	_top_left.modulate.a = 1.0


func _touch(key: String) -> void:
	if _rows.has(key):
		_rows[key].t = Time.get_ticks_msec() / 1000.0


func _on_money(_amount: int, delta: int) -> void:
	_money.text = Wallet.text()
	if delta != 0:
		notify(("+%s" if delta > 0 else "−%s") % Wallet.text(absi(delta)), "money")


# --- Cada frame -----------------------------------------------------------------------

func _process(delta: float) -> void:
	_top_left_t += delta
	if _top_left_t > FADE_AFTER:
		_top_left.modulate.a = move_toward(_top_left.modulate.a, 0.35, delta)  # no desaparece del todo
	_tick += delta
	if _tick > 0.25:
		_tick = 0.0
		_refresh(false)
		_update_waypoint()
		_fps.visible = Settings.show_fps
		if _fps.visible:
			_fps.text = "%d FPS" % Engine.get_frames_per_second()
	# Te caes de sueño: los bordes se oscurecen un poco y respiran
	var tired := clampf((15.0 - Body.get_need("rest")) / 15.0, 0.0, 1.0)
	_vignette.modulate.a = lerpf(_vignette.modulate.a, tired * (0.75 + 0.25 * sin(Time.get_ticks_msec() / 900.0)), 1.0 - exp(-2.0 * delta))


func _refresh(first: bool) -> void:
	_clock.text = "%s %s" % [WorldClock.weekday().left(3).capitalize(), WorldClock.text()]
	_weather.text = Weather.label()
	_money.text = Wallet.text()
	var now := Time.get_ticks_msec() / 1000.0
	var awake := GameState.is_awakened()
	for key in _rows:
		var r: Dictionary = _rows[key]
		var is_stat: bool = key in ["health", "energy", "instability"]
		var value: float = float(GameState.get_stat(key)) if is_stat else Body.get_need(key)
		if first:
			r.bar.value = value
		else:
			r.bar.value = lerpf(r.bar.value, value, 0.35)
		# Inestabilidad: importa cuando SUBE; el resto, cuando baja
		var worrying := (value > 100.0 - SHOW_WHEN_BELOW) if key == "instability" else (value < SHOW_WHEN_BELOW)
		var want := (awake or not is_stat) and (worrying or now - float(r.t) < RECENT)
		var row: Control = r.row
		if want and not row.visible:
			UIAnim.show(row, Vector2(-16, 0))
		elif not want and row.visible and row.modulate.a >= 0.99:
			UIAnim.hide(row)
