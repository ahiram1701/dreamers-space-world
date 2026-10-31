class_name PlayerLook
extends RefCounted
## El aspecto del protagonista: lo eliges al empezar una vida (y lo puedes cambiar en la pausa).
## Se guarda en el mundo (cada vida puede ser distinta). Lo usan el jugador y la vista previa.

const BODIES := ["slim", "average", "sturdy", "tall"]
const BODY_LABELS := ["Delgada", "Media", "Robusta", "Alta"]
const OUTFITS := ["casual", "street", "formal", "work_uniform"]
const OUTFIT_LABELS := ["Casual", "De calle", "Formal", "De trabajo"]
const COLORS := ["#3b6ea5", "#a0522d", "#2f6b4f", "#7b3f8c", "#c9a227", "#b23a3a", "#2b2f3a", "#e8e2d4"]


## El aspecto de este mundo. Las partidas de antes de poder elegirlo siguen como estaban.
static func current() -> Dictionary:
	var saved: Dictionary = WorldDB.get_state("player_look", {}) if WorldDB.is_loaded() else {}
	if not saved.is_empty():
		return saved
	var look := {"outfit": "casual", "primary_color": "#3b6ea5", "secondary_color": "#2b2f3a", "body": "average"}
	if not Settings.player_figure.is_empty():
		look["figure"] = Settings.player_figure
	return look


static func save(look: Dictionary) -> void:
	WorldDB.set_state("player_look", look.duplicate())


## Pone el modelo con su complexión dentro de `holder` (de pie, 1,78 m). Devuelve {model, rig} o {}.
static func build(holder: Node3D, look: Dictionary, seed: int, full_rate: bool = true) -> Dictionary:
	var model := AssetLibrary.character(look, seed)
	if model == null:
		return {}
	var s: Vector3 = TownNPC.BODY_SCALE.get(look.get("body", "average"), Vector3.ONE)
	var placed := AssetLibrary.place(holder, model, Vector3.ZERO, 1.78 * s.y, 0.0, false)
	placed.scale = Vector3(s.x / s.y, 1.0, s.z / s.y)
	var rig := HumanoidRig.new()
	rig.full_rate = full_rate
	model.add_child(rig)
	if not rig.setup(model):
		rig.queue_free()
		rig = null
	return {"model": placed, "rig": rig}
