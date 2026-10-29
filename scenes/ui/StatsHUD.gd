class_name StatsHUD
extends CanvasLayer
## Salud, energía del Ancla e inestabilidad. Solo existe para el jugador tras El Despertar.

const STATS := [
	["health", "Salud", Color("#e05d5d")],
	["energy", "Energía del Ancla", Color("#4fc3f7")],
	["instability", "Inestabilidad", Color("#c77dff")],
]

var _bars: Dictionary = {}


func _ready() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 16)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	add_child(panel)
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 230
	panel.add_child(box)
	for s in STATS:
		var label := Label.new()
		label.text = s[1]
		label.add_theme_font_size_override("font_size", 13)
		box.add_child(label)
		var bar := ProgressBar.new()
		bar.max_value = GameState.MAX_STAT
		bar.show_percentage = false
		bar.custom_minimum_size.y = 10
		var fill := StyleBoxFlat.new()
		fill.bg_color = s[2]
		bar.add_theme_stylebox_override("fill", fill)
		box.add_child(bar)
		_bars[s[0]] = bar
	GameState.stat_changed.connect(_on_stat_changed)
	refresh()


func refresh() -> void:
	visible = GameState.is_awakened()
	for stat in _bars:
		_bars[stat].value = GameState.get_stat(stat)


func _on_stat_changed(stat: String, value: int) -> void:
	if _bars.has(stat):
		create_tween().tween_property(_bars[stat], "value", value, 0.4)
	visible = GameState.is_awakened()
