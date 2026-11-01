class_name PlayerLook
extends RefCounted
## El aspecto del protagonista: lo eliges al empezar una vida. Después cambia como en la vida real:
## la ropa es tuya (la compras, la guardas en el armario, te cambias), el pelo te lo cortas en la
## peluquería y en la pausa solo se corrigen los rasgos del cuerpo. Se guarda en el mundo.
## Lo usan el jugador, la vista previa del creador, el armario, la tienda y la peluquería.

const BODIES := ["slim", "average", "sturdy", "short", "tall"]
const BODY_LABELS := ["Delgada", "Media", "Robusta", "Baja", "Alta"]
const OUTFITS := ["casual", "street", "formal", "work_uniform"]
const OUTFIT_LABELS := ["Casual", "De calle", "Formal", "De trabajo"]
const OUTFIT_PRICE := {"casual": 30, "street": 40, "formal": 75, "work_uniform": 35}
const COLORS := ["#3b6ea5", "#a0522d", "#2f6b4f", "#7b3f8c", "#c9a227", "#b23a3a", "#2b2f3a", "#e8e2d4"]
const COLOR_NAMES := {"#3b6ea5": "azul", "#a0522d": "teja", "#2f6b4f": "verde", "#7b3f8c": "morado", "#c9a227": "mostaza",
	"#b23a3a": "rojo", "#2b2f3a": "negro", "#e8e2d4": "crema"}
const HEIGHT_MIN := 1.55
const HEIGHT_MAX := 1.95
const WARDROBE := "home_wardrobe"   # clave del armario de tu casa (Actions.stash)


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


## Pone el modelo con su complexión y su altura dentro de `holder`. Devuelve {model, rig} o {}.
static func build(holder: Node3D, look: Dictionary, seed: int, full_rate: bool = true) -> Dictionary:
	var model := AssetLibrary.character(look, seed)
	if model == null:
		return {}
	var s: Vector3 = TownNPC.BODY_SCALE.get(look.get("body", "average"), Vector3.ONE)
	var height: float = clampf(float(look.get("height", 1.78 * s.y)), HEIGHT_MIN, HEIGHT_MAX)
	var placed := AssetLibrary.place(holder, model, Vector3.ZERO, height, 0.0, false)
	placed.scale = Vector3(s.x / s.y, 1.0, s.z / s.y)
	var rig := HumanoidRig.new()
	rig.full_rate = full_rate
	model.add_child(rig)
	if not rig.setup(model):
		rig.queue_free()
		rig = null
	return {"model": placed, "rig": rig}


# --- La ropa: objetos de verdad ------------------------------------------------------------

## Nombre de una prenda ("Ropa formal, negro y crema").
static func clothing_name(c: Dictionary) -> String:
	var kind: String = OUTFIT_LABELS[maxi(OUTFITS.find(c.get("outfit", "casual")), 0)]
	var a: String = COLOR_NAMES.get(str(c.get("primary_color", "")), "")
	var b: String = COLOR_NAMES.get(str(c.get("secondary_color", "")), "")
	var colors := a if b.is_empty() or b == a else "%s y %s" % [a, b]
	return "Ropa %s%s" % [kind.to_lower(), (", " + colors) if not colors.is_empty() else ""]


## Crea una prenda (un conjunto) como objeto del mundo. Devuelve su id.
static func make_clothing(c: Dictionary) -> String:
	var data := {"outfit": c.get("outfit", "casual"), "primary_color": c.get("primary_color", "#3b6ea5"),
		"secondary_color": c.get("secondary_color", "#2b2f3a")}
	return WorldDB.add_entity("item", {"name": clothing_name(data), "kind": "consumable", "effect": "warmth", "power": 0,
		"lore": "Un conjunto de ropa. Póntelo en el armario de casa o en un probador.", "tags": ["ropa"], "clothing": data}, "wardrobe")


static func is_clothing(item_id: String) -> bool:
	return WorldDB.get_entity("item", item_id).has("clothing")


## Lo que llevas puesto (id del objeto) o "".
static func wearing() -> String:
	return WorldDB.get_state("wearing", "")


## Ponerte una prenda: la que llevabas va a `put_old_in` ("" = la llevas en la mochila; o la clave
## del armario). Cambia tu aspecto al momento si hay jugador en escena.
static func wear(item_id: String, put_old_in: String = "") -> void:
	var c: Dictionary = WorldDB.get_entity("item", item_id).get("clothing", {})
	if c.is_empty():
		return
	var old := wearing()
	if not old.is_empty() and old != item_id:
		if put_old_in.is_empty():
			Inventory.add(old)
		else:
			_stash_add(put_old_in, old)
	if Inventory.has(item_id):
		Inventory.remove(item_id)
	var wardrobe := Actions.stash(WARDROBE)
	if item_id in wardrobe:
		Actions.stash_take(WARDROBE, item_id)
		Inventory.remove(item_id)
	WorldDB.set_state("wearing", item_id)
	var look := current()
	look.merge(c, true)
	save(look)
	Body.set_clean_clothes()


static func _stash_add(key: String, item_id: String) -> void:
	var all: Dictionary = WorldDB.get_state("stashes", {})
	var list: Array = all.get(key, [])
	if not (item_id in list):
		list.append(item_id)
	all[key] = list
	WorldDB.set_state("stashes", all)


## Toda tu ropa que no llevas puesta: la del armario y la que llevas encima.
static func owned_clothes() -> Array:
	var out := []
	for id in Actions.stash(WARDROBE) + Inventory.items():
		if is_clothing(id) and not (id in out):
			out.append(id)
	return out


## Al empezar una vida: llevas la ropa que elegiste y tienes otra muda en el armario de casa.
static func start_clothes(look: Dictionary) -> void:
	if not WorldDB.get_state("wearing", "").is_empty():
		return
	var worn := make_clothing(look)
	WorldDB.set_state("wearing", worn)
	var spare := {"outfit": "casual" if look.get("outfit", "") != "casual" else "street",
		"primary_color": "#e8e2d4" if look.get("primary_color", "") != "#e8e2d4" else "#3b6ea5", "secondary_color": "#2b2f3a"}
	_stash_add(WARDROBE, make_clothing(spare))


## Lo que hay hoy en la tienda de ropa (cambia cada día, siempre igual ese día).
static func shop_offers(door: String) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(door + str(int(WorldClock.absolute_minutes() / 1440.0)))
	var out := []
	for i in 6:
		var outfit: String = OUTFITS[rng.randi() % OUTFITS.size()]
		var c := {"outfit": outfit, "primary_color": COLORS[rng.randi() % COLORS.size()], "secondary_color": COLORS[rng.randi() % COLORS.size()]}
		out.append({"clothing": c, "name": clothing_name(c), "price": OUTFIT_PRICE[outfit] + rng.randi_range(-4, 12)})
	return out
