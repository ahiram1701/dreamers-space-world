class_name Shops
extends RefCounted
## Los locales (abarrotes, fonda, farmacia, ferretería y la carta de la cafetería): qué venden,
## a qué precio, su horario, quién atiende y cómo se llaman según la época (data/shops.json).
## Comprar crea un objeto de verdad que se come, se bebe, cura o sirve de herramienta.

const PATH := "res://data/shops.json"
const KINDS := ["grocery", "restaurant", "pharmacy", "hardware"]

static var _data := {}


static func data() -> Dictionary:
	if _data.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		_data = parsed if parsed is Dictionary else {"kinds": {}, "eras": {}, "era_labels": {}}
	return _data


static func info(kind: String) -> Dictionary:
	return data().kinds.get(kind, {})


static func is_shop(kind: String) -> bool:
	return data().kinds.has(kind)


static func is_open(kind: String, hour: float) -> bool:
	var i := info(kind)
	return not i.is_empty() and hour >= float(i.open) and hour < float(i.close)


static func hours_text(kind: String) -> String:
	var i := info(kind)
	return "de %d:00 a %d:00" % [int(i.get("open", 9)), int(i.get("close", 20))]


## Cómo se llama ese tipo de local en esta época ("la taberna" en la Antigüedad…).
static func label(kind: String, era: String = "present") -> String:
	return data().era_labels.get(kind, {}).get(era, info(kind).get("label", "la tienda"))


## Los locales que tiene un asentamiento de esa época.
static func for_era(era: String) -> Array:
	return data().eras.get(era, [])


## Compra algo de la lista: cobra y te da el objeto. Devuelve el id ("" si no te alcanza).
static func buy(entry: Dictionary) -> String:
	var price := int(entry.get("price", 0))
	if not Wallet.pay(price):
		return ""
	var id := WorldDB.add_entity("item", {"name": str(entry.name), "kind": "tool" if entry.effect in ["tool", "light"] else "consumable",
		"effect": str(entry.effect), "power": int(entry.get("power", 15)), "lore": str(entry.get("lore", "")),
		"tags": ["comprado", str(entry.name).to_lower()]}.merged(
			{"garment": {"id": str(entry.garment), "color": str(entry.get("color", "#555555"))}} if entry.has("garment") else {}), "shop")
	Inventory.add(id)
	return id
