class_name AssetLibrary
extends RefCounted
## Modelos 3D CC0 (Quaternius, ver assets/CREDITS.md) elegidos a partir de los arquetipos.
## La IA sigue diseñando con valores de archetypes.json ("outfit": "lab_coat", "biome": "ice"…)
## y aquí se traducen a un modelo concreto, siempre con un RNG con semilla: el mismo lugar o
## PNJ se ve igual cada vez. Si falta un modelo, quien llama usa su primitiva de siempre.

const DIR := "res://assets/models/"

## Traje → modelos (hombre, mujer). La figura sale de appearance.figure.
const OUTFITS := {
	"casual": [["Casual", "Casual2", "Beach"], ["Casual"]],
	"work_uniform": [["Worker", "Farmer"], ["Worker"]],
	"lab_coat": [["Suit"], ["Suit", "Formal"]],
	"street": [["Punk", "Casual2"], ["Punk"]],
	"formal": [["Suit"], ["Formal", "Suit"]],
	"ragged": [["Farmer", "Adventurer"], ["Adventurer", "Worker"]],
	"futuristic": [["Spacesuit"], ["SciFi"]],
	"ancient": [["King", "Adventurer"], ["Medieval"]],
	"military": [["Swat"], ["Soldier"]],
	"robe": [["King"], ["Witch", "Medieval"]],
}
## Superficies que no son ropa: no se tiñen con los colores del PNJ.
const NOT_CLOTH := ["skin", "eye", "eyebrows", "hair", "moustache", "beard", "teeth", "mouth"]

const HOUSES_SMALL := ["1Story_GableRoof_Mat", "1Story_Mat", "1Story_RoundRoof_Mat", "2Story_GableRoof_Mat",
	"2Story_Mat", "2Story_RoundRoof_Mat", "2Story_Balcony_Mat", "2Story_2_Mat", "2Story_Columns_Mat"]
const HOUSES_TOWN := ["2Story_Center_Mat", "2Story_Double_Mat", "2Story_Sidehouse_Mat", "2Story_Slim_Mat",
	"2Story_Stairs_Mat", "3Story_Balcony_Mat", "3Story_Slim_Mat", "3Story_Small_Mat", "2Story_Sign_Mat", "1Story_Sign_Mat"]
const HOUSES_CITY := ["4Story_Center_Mat", "4Story_Mat", "4Story_Wide_2Doors_Mat", "4Story_Wide_2Doors_Roof_Mat",
	"6Story_Stack_Mat", "2Story_Wide_Mat", "2Story_Wide_2Doors_Mat"]

## Bioma → [árboles, arbustos/plantas, rocas]
const NATURE := {
	"temperate": [["CommonTree_1", "CommonTree_2", "CommonTree_3", "CommonTree_4", "CommonTree_5", "BirchTree_1", "BirchTree_2", "Willow_1", "Willow_2"],
		["Bush_1", "Bush_2", "BushBerries_1", "Flowers", "Plant_1", "Plant_2", "Grass", "Grass_2"], ["Rock_Moss_1", "Rock_Moss_2", "Rock_Moss_3", "Rock_1"]],
	"jungle": [["PalmTree_1", "PalmTree_2", "Willow_3", "Willow_4", "CommonTree_4", "CommonTree_5"],
		["Plant_3", "Plant_4", "Plant_5", "BushBerries_2", "Bush_1", "Grass"], ["Rock_Moss_4", "Rock_Moss_5", "Rock_Moss_6"]],
	"ocean": [["PalmTree_1", "PalmTree_2", "PalmTree_3", "PalmTree_4"], ["Plant_1", "Grass_2", "Bush_2"], ["Rock_1", "Rock_2", "Rock_3"]],
	"desert": [["Cactus_1", "Cactus_2", "Cactus_3", "Cactus_4", "Cactus_5"], ["Plant_5", "Grass_2"], ["Rock_2", "Rock_4", "Rock_5", "Rock_6"]],
	"ice": [["PineTree_Snow_1", "CommonTree_Snow_1"], ["Bush_2"], ["Rock_Snow_1", "Rock_3", "Rock_7"]],
	"barren": [["CommonTree_Dead_1"], ["Grass_2"], ["Rock_1", "Rock_2", "Rock_4", "Rock_5", "Rock_6", "Rock_7"]],
	"volcanic": [["CommonTree_Dead_1"], [], ["Rock_1", "Rock_4", "Rock_6", "Rock_7"]],
	"urban": [["CommonTree_1", "BirchTree_3"], ["Bush_1", "Flowers"], ["Rock_1"]],
	"pine": [["PineTree_1", "PineTree_2", "PineTree_3", "PineTree_4", "PineTree_5"], ["Bush_1", "Plant_2"], ["Rock_Moss_7", "Rock_3"]],
}

static var _cache := {}
## Las ventanas de todos los edificios comparten material: WorldClock las enciende de noche.
static var window_material: StandardMaterial3D


static func path(pack: String, model: String) -> String:
	return "%s%s/%s.glb" % [DIR, pack, model]


## Instancia un modelo o null si no existe.
static func instance(pack: String, model: String) -> Node3D:
	var p := path(pack, model)
	if not _cache.has(p):
		_cache[p] = load(p) if ResourceLoader.exists(p) else null
	var scene: PackedScene = _cache[p]
	return scene.instantiate() as Node3D if scene else null


## Persona con su traje y sus colores. Devuelve el nodo del modelo (o null).
static func character(appearance: Dictionary, rng_seed: int) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var figure = appearance.get("figure")
	var feminine: bool = figure == "feminine" if figure in ["feminine", "masculine"] else rng.randf() < 0.5
	var options: Array = OUTFITS.get(appearance.get("outfit", "casual"), OUTFITS.casual)[1 if feminine else 0]
	var model := instance("modular_women" if feminine else "modular_men", options[rng.randi() % options.size()])
	if model == null:
		return null
	var primary := Color(appearance.get("primary_color", "#5a6f8a"))
	var secondary := Color(appearance.get("secondary_color", "#c9b48a"))
	for mi in _meshes(model):
		var legs: bool = mi.name.ends_with("Legs") or mi.name.ends_with("Feet")
		var cloth_index := 0
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i) as StandardMaterial3D
			if src == null or _is_body(src.resource_name):
				continue
			# Solo la prenda principal de cada pieza lleva el color del PNJ; el resto, matizado
			var m := src.duplicate() as StandardMaterial3D
			var tint := secondary if legs else primary
			m.albedo_color = tint if cloth_index == 0 else src.albedo_color.lerp(tint, 0.35)
			m.roughness = 0.85
			mi.set_surface_override_material(i, m)
			cloth_index += 1
	return model


## Edificio para un asentamiento. `size_class`: "small" (casas), "town", "city".
static func building(size_class: String, rng: RandomNumberGenerator, wall_tint: Color = Color(0, 0, 0, 0)) -> Node3D:
	var list: Array = {"small": HOUSES_SMALL, "town": HOUSES_TOWN, "city": HOUSES_CITY}.get(size_class, HOUSES_SMALL)
	var model := instance("buildings_pack_3", list[rng.randi() % list.size()])
	if model:
		_dress_building(model, wall_tint)
	return model


static func _dress_building(model: Node3D, wall_tint: Color) -> void:
	for mi in _meshes(model):
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i) as StandardMaterial3D
			if src == null:
				continue
			if src.resource_name == "Glass":
				mi.set_surface_override_material(i, _windows())
			elif wall_tint.a > 0.0 and src.resource_name in ["Main", "Bricks"]:
				var m := src.duplicate() as StandardMaterial3D
				m.albedo_color = src.albedo_color.lerp(wall_tint, 0.6 if src.resource_name == "Main" else 0.3)
				mi.set_surface_override_material(i, m)


## Un edificio concreto por nombre, con ventanas que se encienden y su color de fachada.
static func building_named(model_name: String, wall_tint: Color = Color(0, 0, 0, 0)) -> Node3D:
	var model := instance("buildings_pack_3", model_name)
	if model:
		_dress_building(model, wall_tint)
	return model


## Árbol, arbusto o roca del bioma. kind: 0 árbol, 1 planta, 2 roca.
static func nature(biome: String, kind: int, rng: RandomNumberGenerator) -> Node3D:
	var set: Array = NATURE.get(biome, NATURE.temperate)
	var list: Array = set[kind]
	if list.is_empty():
		return null
	return instance("nature_pack", list[rng.randi() % list.size()])


## Tamaño real del modelo (para escalarlo y darle colisión).
static func bounds(node: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mi in _meshes(node):
		var t := Transform3D.IDENTITY
		var n: Node = mi
		while n != node and n != null:
			if n is Node3D:
				t = (n as Node3D).transform * t
			n = n.get_parent()
		var a: AABB = t * mi.mesh.get_aabb()
		out = a if first else out.merge(a)
		first = false
	return out


## Pone el modelo en el mundo con la altura pedida. `collide`: false, true (caja) o "trunk"
## (solo un cilindro fino en la base: se puede pasar bajo la copa de un árbol).
## Devuelve el nodo raíz (posición = base del modelo).
static func place(parent: Node3D, model: Node3D, pos: Vector3, target_height: float, yaw: float, collide: Variant) -> Node3D:
	var b := bounds(model)
	var s := target_height / maxf(b.size.y, 0.01)
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = yaw
	model.scale = Vector3.ONE * s
	model.position = -Vector3(b.get_center().x, b.position.y, b.get_center().z) * s
	root.add_child(model)
	root.set_meta("size", b.size * s)
	if collide is String and collide == "trunk":
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		cs.shape = CylinderShape3D.new()
		cs.shape.radius = clampf(minf(b.size.x, b.size.z) * s * 0.08, 0.2, 0.45)
		cs.shape.height = minf(target_height, 4.0)
		cs.position.y = cs.shape.height / 2.0
		body.add_child(cs)
		root.add_child(body)
	elif collide:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		cs.shape = BoxShape3D.new()
		cs.shape.size = Vector3(b.size.x, b.size.y, b.size.z) * s
		cs.position.y = b.size.y * s / 2.0
		body.add_child(cs)
		root.add_child(body)
	parent.add_child(root)
	return root


static func _windows() -> StandardMaterial3D:
	if window_material == null:
		window_material = StandardMaterial3D.new()
		window_material.albedo_color = Color("#4a6378")
		window_material.metallic = 0.6
		window_material.roughness = 0.15
		window_material.emission_enabled = true
		window_material.emission = Color("#ffc878")
		window_material.emission_energy_multiplier = 0.0
	return window_material


static func _is_body(material_name: String) -> bool:
	var n := material_name.to_lower()
	for k in NOT_CLOTH:
		if n.begins_with(k):
			return true
	return false


static func _meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D and (node as MeshInstance3D).mesh:
		out.append(node)
	for c in node.get_children():
		out.append_array(_meshes(c))
	return out
