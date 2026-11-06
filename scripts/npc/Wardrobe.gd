class_name Wardrobe
extends RefCounted
## La ropa por prendas. Debajo va el modelo de cuerpo entero (la «ropa base»: camiseta y
## pantalón, traje…), y encima las capas: impermeable, abrigo, suéter, gorra, bufanda, mochila…
## (data/clothing.json). Las prendas del torso se hacen copiando la malla del cuerpo, un poco
## inflada y con el mismo esqueleto, así que se mueven con la animación. Las del resto (gorra,
## bufanda, mochila, lentes) van sujetas a su hueso.
##
## Una sola fuente de verdad: lo que se ve es lo que se describe a la IA (`describe`), y lo que
## la IA dice que alguien lleva se comprueba contra esto (`mentions_missing`).

const GROUP := "garment"
## Lo que es la ropa base de cada estilo (modelos de AssetLibrary.OUTFITS).
const BASE_WORDS := {"casual": "camiseta y pantalón", "street": "sudadera y pantalón de calle",
	"formal": "camisa, saco y pantalón de vestir", "work_uniform": "ropa de trabajo (overol)", "lab_coat": "bata",
	"ragged": "ropa vieja y gastada", "futuristic": "traje espacial", "ancient": "ropa antigua", "military": "uniforme militar",
	"robe": "túnica"}
## Huesos de cada zona (los de la malla original).
const TORSO_BONES := ["Hips", "Abdomen", "Torso", "Chest", "Shoulder.L", "Shoulder.R"]
const ARM_BONES := ["UpperArm.L", "UpperArm.R", "LowerArm.L", "LowerArm.R"]
const LEG_BONES := ["UpperLeg.L", "UpperLeg.R"]

static var _data: Dictionary = {}


static func catalog() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open("res://data/clothing.json", FileAccess.READ)
		if f:
			var parsed = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				_data = parsed.get("garments", {})
	return _data


static func garment(id: String) -> Dictionary:
	return catalog().get(id, {})


## Busca una prenda por cómo se dice («chubasquero» → raincoat). "" si no es ropa del catálogo.
static func find(text: String) -> String:
	var low := text.to_lower()
	var best := ""
	var best_len := 0
	for id in catalog():
		for n in catalog()[id].names:
			if low.contains(str(n)) and str(n).length() > best_len:
				best = id
				best_len = str(n).length()
	return best


# --- Qué se pone cada quien -----------------------------------------------------------------

## Capas que alguien lleva ahora: las suyas de siempre más lo que pide el tiempo que hace.
## Determinista por persona y día (no cambia de ropa cada vez que la ves).
static func for_weather(entity: Dictionary, outdoors: bool = true) -> Array:
	var look: Dictionary = entity.get("appearance", {})
	var own: Array = look.get("layers", []).filter(func(l): return not bool(l.get("weather", false)))
	if not outdoors or str(look.get("outfit", "")) in ["futuristic", "military"]:
		return own
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(entity.get("id", entity.get("name", ""))) + str(int(WorldClock.absolute_minutes() / 1440.0)))
	var h := WorldClock.hour()
	var night := h >= 20.0 or h < 7.0
	var w := Weather.current()
	var out := own.duplicate()
	var has := func(layer: String) -> bool: return out.any(func(l): return garment(str(l.id)).get("layer", "") == layer)
	if w == "rain":
		if not has.call("outer") or rng.randf() < 0.75:
			out = out.filter(func(l): return garment(str(l.id)).get("layer", "") != "outer")
			out.append(_layer("raincoat", rng, true))
	elif (night and rng.randf() < 0.7) or (w in ["wind", "fog"] and rng.randf() < 0.6):
		if not has.call("outer"):
			out.append(_layer(["jacket", "coat", "coat"][rng.randi() % 3] if night else "jacket", rng, true))
		if night and rng.randf() < 0.25 and not has.call("neck"):
			out.append(_layer("scarf", rng, true))
	elif w == "cloudy" and rng.randf() < 0.3 and not has.call("outer") and not has.call("mid"):
		out.append(_layer("sweater", rng, true))
	return out


static func _layer(id: String, rng: RandomNumberGenerator, weather: bool = false) -> Dictionary:
	var colors: Array = garment(id).get("colors", ["#444444"])
	var l := {"id": id, "color": str(colors[rng.randi() % colors.size()])}
	if weather:
		l["weather"] = true
	return l


## Capas propias de alguien según su oficio (una gorra al repartidor, delantal a quien cocina…).
static func for_job(job: String, rng: RandomNumberGenerator) -> Array:
	var low := job.to_lower()
	var out := []
	if low.contains("barista") or low.contains("cociner") or low.contains("panader") or low.contains("fonda"):
		out.append(_layer("apron", rng))
	if low.contains("repartidor") or low.contains("jardiner") or low.contains("pescador") or low.contains("taxista"):
		if rng.randf() < 0.7:
			out.append(_layer("cap", rng))
	if low.contains("estudiante") and rng.randf() < 0.7:
		out.append(_layer("backpack", rng))
	if (low.contains("jubilad") or low.contains("maestr") or low.contains("oficinista")) and rng.randf() < 0.5:
		out.append(_layer("glasses", rng))
	if low.contains("faro") and rng.randf() < 0.9:
		out.append(_layer("sweater", rng))
	return out


# --- Cómo se describe -----------------------------------------------------------------------

static func color_name(hex: String) -> String:
	if not Color.html_is_valid(hex):
		return ""
	var c := Color(hex)
	if c.v < 0.18:
		return "negro"
	if c.s < 0.15:
		return "blanco" if c.v > 0.85 else ("gris claro" if c.v > 0.6 else "gris")
	var hue := c.h * 360.0
	if (hue < 45.0 or hue > 340.0) and c.v < 0.55 and c.s < 0.7:
		return "café"
	if hue >= 20.0 and hue < 50.0 and c.s < 0.45:
		return "beige" if c.v > 0.65 else "café"
	if hue < 15.0 or hue >= 340.0:
		return "rojo" if c.v > 0.4 else "granate"
	if hue < 40.0:
		return "naranja"
	if hue < 65.0:
		return "amarillo" if c.v > 0.6 else "mostaza"
	if hue < 160.0:
		return "verde"
	if hue < 200.0:
		return "turquesa"
	if hue < 255.0:
		return "azul" if c.v > 0.3 else "azul marino"
	if hue < 300.0:
		return "morado"
	return "rosa"


## «impermeable amarillo, camiseta y pantalón (azul y gris); sin abrigo ni sombrero».
static func describe(look: Dictionary, layers: Array = []) -> String:
	if layers.is_empty():
		layers = look.get("layers", [])
	var base: String = BASE_WORDS.get(str(look.get("outfit", "casual")), "ropa normal")
	var c1 := color_name(str(look.get("primary_color", "")))
	var c2 := color_name(str(look.get("secondary_color", "")))
	var colors := c1 if c2.is_empty() or c2 == c1 else "%s y %s" % [c1, c2]
	var worn := PackedStringArray()
	var layers_seen := {}
	for l in layers:
		var g := garment(str(l.get("id", "")))
		if g.is_empty():
			continue
		layers_seen[str(l.id)] = true
		var col := color_name(str(l.get("color", "")))
		worn.append(str(g.name) + ((" " + _agree(str(g.name), col)) if not col.is_empty() else ""))
	worn.append(base + ((" (%s)" % colors) if not colors.is_empty() else ""))
	var missing := PackedStringArray()
	for id in ["coat", "raincoat", "jacket", "sweater", "scarf", "hat", "cap", "backpack"]:
		if not layers_seen.has(id):
			missing.append(str(garment(id).name))
	return ", ".join(worn) + ("; NADA más (sin %s)" % " ni ".join(missing) if not missing.is_empty() else "")


## Concordancia del color con la prenda («bufanda roja», «lentes negros»).
static func _agree(noun: String, col: String) -> String:
	var fem := noun.ends_with("a") or noun in ["gorra"]
	var plural := noun.ends_with("s")
	var out := col
	if fem and col.ends_with("o"):
		out = col.left(-1) + "a"
	if plural and not out.ends_with("s"):
		out += "es" if out.ends_with("l") or out.ends_with("n") or out.ends_with("r") else "s"
	return out


## ¿Lleva esa prenda? (por id del catálogo o por cómo se dice).
static func wears(layers: Array, what: String) -> bool:
	var id := what if catalog().has(what) else find(what)
	return not id.is_empty() and layers.any(func(l): return str(l.get("id", "")) == id)


## Prendas del catálogo que `text` menciona y que no están en `layers` (para quitar de una
## acotación «se ajusta el cuello del impermeable» si no lleva impermeable). Ignora la ropa base.
static func mentions_missing(text: String, layers: Array, base_outfit: String = "casual") -> Array:
	var low := text.to_lower()
	var base: String = BASE_WORDS.get(base_outfit, "")
	var out := []
	for id in catalog():
		if wears(layers, id):
			continue
		for n in catalog()[id].names:
			if low.contains(str(n)) and not base.contains(str(n)):
				out.append(id)
				break
	return out


# --- Cómo se ve -----------------------------------------------------------------------------

static func undress(model: Node3D) -> void:
	for n in model.find_children("*", "", true, false):
		if n.is_in_group(GROUP):
			n.get_parent().remove_child(n)
			n.queue_free()


## Pone las capas sobre un modelo de AssetLibrary.character (con su Skeleton3D).
static func dress(model: Node3D, layers: Array) -> void:
	if model == null or layers.is_empty():
		return
	var sks := model.find_children("*", "Skeleton3D", true, false)
	if sks.is_empty():
		return
	var sk: Skeleton3D = sks[0]
	var body: MeshInstance3D = null
	var legs: MeshInstance3D = null
	var head: MeshInstance3D = null
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		if mi.is_in_group(GROUP):
			continue
		if mi.name.ends_with("_Body"):
			body = mi
		elif mi.name.ends_with("_Legs"):
			legs = mi
		elif mi.name.ends_with("_Head"):
			head = mi
	var unit := _unit(sk, head)  # unidades de malla por metro
	for l in layers:
		var g := garment(str(l.get("id", "")))
		if g.is_empty():
			continue
		var color := Color(str(l.get("color", "#555555")))
		match str(g.shape):
			"shell":
				var bones: Array = TORSO_BONES.duplicate()
				if g.get("arms", true):
					bones.append_array(ARM_BONES)
				if body:
					_shell(sk, body, bones, float(g.thick) * unit, color, str(l.id))
				if g.get("legs", false) and legs:
					_shell(sk, legs, ["Hips"] + LEG_BONES, float(g.thick) * unit * 1.3, color, str(l.id), 0.55)
				if g.get("hood", false):
					_rigid(sk, "Neck", _hood_mesh(unit), color, Vector3(0, 0.07 * unit, 0.02 * unit), str(l.id))
			"apron":
				if body:
					_rigid(sk, "Hips", _box(Vector3(0.32, 0.55, 0.012) * unit), color, Vector3(0, 0.0, 0.02 * unit), str(l.id), "front", 0.095 * unit)
			"scarf":
				_rigid(sk, "Neck", _torus(0.075 * unit, 0.03 * unit), color, Vector3.ZERO, str(l.id))
			"cap", "hat", "beanie":
				_hat(sk, head, str(g.shape), color, unit, str(l.id))
			"backpack":
				_rigid(sk, "Chest", _box(Vector3(0.3, 0.4, 0.14) * unit), color, Vector3.ZERO, str(l.id), "back", 0.16 * unit)
			"glasses":
				_rigid(sk, "Head", _box(Vector3(0.16, 0.04, 0.02) * unit), color, Vector3(0, 0, 0.1 * unit), str(l.id), "front", 0.118 * unit)


## Cuántas unidades de la malla son un metro (los modelos vienen a escala diminuta).
static func _unit(sk: Skeleton3D, head: MeshInstance3D) -> float:
	var top := 0.0
	if head:
		var hb := head.get_aabb()
		top = (head.transform * (hb.position + hb.size)).z
	var foot := sk.find_bone("Foot.L")
	var floor_z: float = sk.get_bone_global_rest(foot).origin.z - 0.0005 if foot >= 0 else 0.0
	var h := top - minf(floor_z, 0.0)
	return h / 1.75 if h > 0.0 else 0.0105


## Hacia dónde mira el cuerpo en el espacio del esqueleto (la cara): el lado con menos malla.
static func _front_axis(sk: Skeleton3D) -> Vector3:
	return Vector3(0, -1, 0)  # modelos de Quaternius: la cara hacia -Y (comprobado con el AABB)


static func _material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.8
	m.cull_mode = BaseMaterial3D.CULL_BACK
	return m


## Copia de la parte de la malla de esos huesos, inflada `thick` hacia fuera. Usa la misma piel
## (Skin) que el original: se deforma igual. `max_down`: hasta qué fracción de la pierna llega.
static func _shell(sk: Skeleton3D, src: MeshInstance3D, bones: Array, thick: float, color: Color, id: String, max_down: float = 1.0) -> void:
	var mesh := src.mesh
	var skin := src.skin
	if mesh == null:
		return
	var bind_name := {}
	if skin:
		for i in skin.get_bind_count():
			var n := skin.get_bind_name(i)
			if n.is_empty() and skin.get_bind_bone(i) >= 0:
				n = sk.get_bone_name(skin.get_bind_bone(i))
			bind_name[i] = n
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var bone_arr := PackedInt32Array()
	var weight_arr := PackedFloat32Array()
	var idx := PackedInt32Array()
	var knee_z := INF
	var hip_z := 0.0
	var lk := sk.find_bone("LowerLeg.L")
	var hp := sk.find_bone("Hips")
	if lk >= 0 and hp >= 0:
		hip_z = sk.get_bone_global_rest(hp).origin.z
		knee_z = sk.get_bone_global_rest(lk).origin.z
	var min_z := hip_z - (hip_z - knee_z) * max_down if knee_z < INF else -INF
	var weld := {}  # posición -> normal media (sin grietas en las costuras)
	var surfaces := []
	for s in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		if arr[Mesh.ARRAY_BONES] == null or arr[Mesh.ARRAY_INDEX] == null:
			continue
		surfaces.append(arr)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		for i in v.size():
			var key := v[i].snapped(Vector3.ONE * 0.00001)
			weld[key] = weld.get(key, Vector3.ZERO) + n[i]
	for arr in surfaces:
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var b: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var w: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		var ind: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var per := b.size() / maxi(v.size(), 1)
		var keep := PackedByteArray()
		keep.resize(v.size())
		for i in v.size():
			var best := 0
			for k in per:
				if w[i * per + k] > w[i * per + best]:
					best = k
			var bn: String = bind_name.get(b[i * per + best], "")
			keep[i] = 1 if bn in bones and v[i].z >= min_z else 0
		var remap := {}
		for t in range(0, ind.size(), 3):
			if keep[ind[t]] == 0 or keep[ind[t + 1]] == 0 or keep[ind[t + 2]] == 0:
				continue
			for k in 3:
				var vi := ind[t + k]
				if not remap.has(vi):
					remap[vi] = verts.size()
					var nn: Vector3 = weld.get(v[vi].snapped(Vector3.ONE * 0.00001), Vector3.UP).normalized()
					verts.append(v[vi] + nn * thick)
					norms.append(nn)
					for q in 4:
						bone_arr.append(b[vi * per + q] if q < per else 0)
						weight_arr.append(w[vi * per + q] if q < per else 0.0)
				idx.append(remap[vi])
	if idx.is_empty():
		return
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = verts
	out[Mesh.ARRAY_NORMAL] = norms
	out[Mesh.ARRAY_BONES] = bone_arr
	out[Mesh.ARRAY_WEIGHTS] = weight_arr
	out[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	am.surface_set_material(0, _material(color))
	var mi := MeshInstance3D.new()
	mi.name = "Garment_" + id
	mi.mesh = am
	mi.skin = skin
	mi.transform = src.transform
	mi.add_to_group(GROUP)
	src.get_parent().add_child(mi)
	mi.skeleton = mi.get_path_to(sk)


## Algo rígido sujeto a un hueso. `side`: "front"/"back" lo separa del cuerpo `offset` unidades.
static func _rigid(sk: Skeleton3D, bone: String, mesh: Mesh, color: Color, at: Vector3, id: String, side: String = "", offset: float = 0.0) -> void:
	var bi := sk.find_bone(bone)
	if bi < 0:
		return
	var att := BoneAttachment3D.new()
	att.bone_name = bone
	att.add_to_group(GROUP)
	sk.add_child(att)
	var rest := sk.get_bone_global_rest(bi)
	var pos := rest.origin + at
	if side == "front":
		pos += _front_axis(sk) * offset
	elif side == "back":
		pos -= _front_axis(sk) * offset
	var mi := MeshInstance3D.new()
	mi.name = "Garment_" + id
	mi.mesh = mesh
	mi.material_override = _material(color)
	# Colocado en el espacio del esqueleto (Z arriba, -Y delante) y pasado al del hueso
	var t := Transform3D(Basis(Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0)), pos)
	mi.transform = rest.affine_inverse() * t
	att.add_child(mi)


static func _hat(sk: Skeleton3D, head: MeshInstance3D, shape: String, color: Color, unit: float, id: String) -> void:
	var top := Vector3(0, 0, 0)
	var r := 0.11 * unit
	if head:
		var hb := head.get_aabb()
		var c := head.transform * (hb.position + hb.size * 0.5)
		top = Vector3(c.x, c.y, (head.transform * (hb.position + hb.size)).z)
		r = minf(hb.size.x, hb.size.y) * 0.5 * 0.95
	var hi := sk.find_bone("Head")
	if hi < 0:
		return
	var at := top - sk.get_bone_global_rest(hi).origin
	match shape:
		"cap":
			_rigid(sk, "Head", _dome(r * 1.02, r * 0.75), color, at - Vector3(0, 0, r * 0.62), id)
			_rigid(sk, "Head", _cyl(r * 0.85, r * 0.85, r * 0.06), color, at - Vector3(0, r * 0.55, r * 0.55), id)
		"hat":
			_rigid(sk, "Head", _cyl(r * 0.9, r * 0.95, r * 0.75), color, at - Vector3(0, 0, r * 0.15), id)
			_rigid(sk, "Head", _cyl(r * 1.7, r * 1.7, r * 0.06), color, at - Vector3(0, 0, r * 0.5), id)
		"beanie":
			_rigid(sk, "Head", _dome(r * 1.05, r * 0.95), color, at - Vector3(0, 0, r * 0.75), id)


static func _hood_mesh(unit: float) -> Mesh:
	return _dome(0.13 * unit, 0.08 * unit)


static func _box(size: Vector3) -> Mesh:
	var m := BoxMesh.new()
	m.size = Vector3(size.x, size.y, size.z)
	return m


static func _torus(r: float, tube: float) -> Mesh:
	var m := TorusMesh.new()
	m.inner_radius = r - tube
	m.outer_radius = r + tube
	return m


static func _cyl(top: float, bottom: float, h: float) -> Mesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = h
	return m


static func _dome(r: float, h: float) -> Mesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = h * 2.0
	m.is_hemisphere = true
	return m
