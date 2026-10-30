extends Node
## Única fuente de verdad sobre la forma de cada entidad del mundo.
## De SPECS sale el JSON schema que se envía a Ollama, la descripción del formato que se pone
## en el prompt y la validación posterior.
##
## Tipos de campo: string, int, float, bool, color (#rrggbb), enum (valores de archetypes.json),
## array (items + min/max), object (fields).
## - "opt": true      → campo opcional.
## - "default": valor → si falta o no es válido se usa este valor (aviso, no error).
## - "lenient": true  → en un array, los elementos inválidos se descartan en vez de fallar.
##
## Filosofía: los modelos no siempre respetan el esquema (traducen valores al español, devuelven
## texto donde va un objeto…). Lo esencial (frases, nombres, descripciones) es obligatorio; los
## detalles se reparan con sinónimos y valores por defecto para no tirar una respuesta buena.

const ARCHETYPES_PATH := "res://data/archetypes.json"

## Algo que ocurre de verdad en el mundo (lo ejecuta Actions.gd). Campos planos y opcionales:
## a los modelos les cuesta menos acertar con un objeto plano que con uno por tipo de acción.
const ACTION := {"t": "object", "fields": {
	"type": {"t": "enum", "from": "npc_action"},
	"item_name": {"t": "string", "min": 2, "max": 70, "opt": true},
	"item_description": {"t": "string", "min": 5, "max": 300, "opt": true},
	"item_effect": {"t": "enum", "from": "item_effect", "default": "none"},
	"lent": {"t": "bool", "default": false},
	"target": {"t": "string", "min": 1, "max": 80, "opt": true},
	"amount": {"t": "int", "min": -30, "max": 30, "default": 0},
	"text": {"t": "string", "min": 3, "max": 300, "opt": true},
	# Reacción de una persona a lo que hace el jugador (npc_react) e irse encerrado (go_inside)
	"gesture": {"t": "enum", "from": "gesture", "opt": true},
	"emotion": {"t": "enum", "from": "emotion", "opt": true},
	"behavior": {"t": "enum", "from": "npc_behavior", "opt": true},
	"line": {"t": "string", "min": 1, "max": 200, "opt": true},
	"locked": {"t": "bool", "default": false},
	# Dinero (pagar, cobrar, precio de lo que te dan, recompensa de un encargo)
	"price": {"t": "int", "min": 0, "max": 200, "default": 0},
	# Gente nueva (spawn_npc): nombre y oficio
	"name": {"t": "string", "min": 2, "max": 40, "opt": true},
	"occupation": {"t": "string", "min": 2, "max": 80, "opt": true},
	# Trabajo (hire_player): horario del turno
	"start_hour": {"t": "int", "min": 0, "max": 23, "opt": true},
	"end_hour": {"t": "int", "min": 0, "max": 23, "opt": true},
	# Lo que se construye (place_object): para qué sirve y su forma en piezas
	"function": {"t": "enum", "from": "placed_function", "default": "none"},
	"parts": {"t": "array", "min": 0, "max": 14, "opt": true, "lenient": true, "items": {"t": "object", "fields": {
		"shape": {"t": "enum", "from": "part_shape", "default": "box"},
		"size": {"t": "array", "min": 3, "max": 3, "items": {"t": "float", "min": 0.02, "max": 6.0}},
		"pos": {"t": "array", "min": 3, "max": 3, "items": {"t": "float", "min": -4.0, "max": 6.0}},
		"color": {"t": "color", "default": "#8b6b4a"},
	}}},
	# Frase de narración de este paso (world_action.steps)
	"narration": {"t": "string", "min": 2, "max": 300, "opt": true},
}}

const SPECS := {
	"npc": {
		"name": {"t": "string", "min": 2, "max": 40},
		"age": {"t": "int", "min": 5, "max": 900, "default": 35},
		"occupation": {"t": "string", "min": 2, "max": 80},
		"personality": {"t": "array", "min": 1, "max": 5, "lenient": true, "items": {"t": "string", "min": 2, "max": 30}},
		"goals": {"t": "array", "min": 1, "max": 3, "lenient": true, "items": {"t": "string", "min": 3, "max": 120}},
		"secret": {"t": "string", "min": 3, "max": 200},
		"greeting": {"t": "string", "min": 2, "max": 240},
		"appearance": {"t": "object", "default": {}, "fields": {
			"figure": {"t": "enum", "from": "npc_figure", "opt": true},
			"body": {"t": "enum", "from": "npc_body", "default": "average"},
			"outfit": {"t": "enum", "from": "npc_outfit", "default": "casual"},
			"primary_color": {"t": "color", "default": "#5a6f8a"},
			"secondary_color": {"t": "color", "default": "#c9b48a"},
		}},
		"tags": {"t": "array", "min": 0, "max": 6, "opt": true, "lenient": true, "items": {"t": "string", "min": 2, "max": 24}},
	},
	"location": {
		"name": {"t": "string", "min": 2, "max": 80},
		"kind": {"t": "enum", "from": "location_kind", "default": "wilderness"},
		"biome": {"t": "enum", "from": "biome", "default": "barren"},
		"era": {"t": "enum", "from": "era", "default": "far_future"},
		"description": {"t": "string", "min": 10, "max": 500},
		"gravity": {"t": "float", "min": 0.1, "max": 3.0, "default": 1.0},
		"seed": {"t": "int", "min": 0, "max": 2147483647, "default": 7},
		"sky_color": {"t": "color", "default": "#7090c0"},
		"points_of_interest": {"t": "array", "min": 1, "max": 6, "lenient": true, "items": {"t": "string", "min": 2, "max": 60}},
		"tags": {"t": "array", "min": 0, "max": 6, "opt": true, "lenient": true, "items": {"t": "string", "min": 2, "max": 24}},
	},
	"item": {
		"name": {"t": "string", "min": 2, "max": 70},
		"kind": {"t": "enum", "from": "item_kind", "default": "artifact"},
		"effect": {"t": "enum", "from": "item_effect", "default": "none"},
		"power": {"t": "int", "min": 0, "max": 100, "default": 20},
		"lore": {"t": "string", "min": 5, "max": 300},
		"tags": {"t": "array", "min": 0, "max": 6, "opt": true, "lenient": true, "items": {"t": "string", "min": 2, "max": 24}},
	},
	# No es una entidad del mundo: es la respuesta de un PNJ en una conversación.
	"dialogue_turn": {
		"line": {"t": "string", "min": 1, "max": 600},
		"emotion": {"t": "enum", "from": "emotion", "default": "neutral"},
		# Si el modelo no las da, el jugador siempre puede seguir: no se tira la frase del PNJ
		"choices": {"t": "array", "min": 2, "max": 4, "lenient": true, "default": [
				{"text": "Sigue, te escucho.", "tone": "friendly"}, {"text": "Cambiemos de tema.", "tone": "curious"},
				{"text": "Tengo que irme, hasta luego.", "tone": "kind"}], "items": {"t": "object", "fields": {
			"text": {"t": "string", "min": 2, "max": 120},
			"tone": {"t": "enum", "from": "tone", "default": "friendly"},
		}}},
		"new_facts": {"t": "array", "min": 0, "max": 2, "opt": true, "lenient": true, "items": {"t": "string", "min": 3, "max": 160}},
		"relationship_delta": {"t": "int", "min": -10, "max": 10, "default": 0},
		"trait_signals": {"t": "array", "min": 0, "max": 3, "opt": true, "lenient": true, "items": {"t": "object", "fields": {
			"trait": {"t": "enum", "from": "player_trait"},
			"delta": {"t": "int", "min": -3, "max": 3, "default": 1},
		}}},
		"end_conversation": {"t": "bool", "default": false},
		"actions": {"t": "array", "min": 0, "max": 4, "opt": true, "lenient": true, "items": ACTION},
	},
	# El jugador hace algo libre en el mundo ("busco en el cajón", "pesco en el muelle").
	"world_action": {
		"narration": {"t": "string", "min": 5, "max": 800},
		# Lo que hace el personaje, en orden y con su narración: ir, hacer el gesto, usar algo, que alguien reaccione…
		"steps": {"t": "array", "min": 0, "max": 8, "opt": true, "lenient": true, "items": ACTION},
		"actions": {"t": "array", "min": 0, "max": 6, "opt": true, "lenient": true, "items": ACTION},
		"minutes": {"t": "int", "min": 0, "max": 480, "default": 5},
	},
	# Dos vecinos charlan entre ellos (se ve en bocadillos). "who": "a" o "b".
	"ambient_chat": {
		"lines": {"t": "array", "min": 2, "max": 4, "lenient": true, "items": {"t": "object", "fields": {
			"who": {"t": "string", "min": 1, "max": 40},
			"text": {"t": "string", "min": 2, "max": 160},
		}}},
	},
	# El momento en que el jugador descubre la brecha. Una vez por partida.
	"awakening": {
		"origin": {"t": "enum", "from": "awakening_origin", "default": "natural_anomaly"},
		"title": {"t": "string", "min": 2, "max": 60},
		"narration": {"t": "string", "min": 80, "max": 1500},
		"source_description": {"t": "string", "min": 20, "max": 400},
		"anchor": {"t": "object", "fields": {
			"name": {"t": "string", "min": 2, "max": 40},
			"description": {"t": "string", "min": 10, "max": 300},
			"base": {"t": "enum", "from": "anchor_base", "default": "none"},
		}},
		"canon_facts": {"t": "array", "min": 2, "max": 3, "lenient": true, "items": {"t": "string", "min": 10, "max": 200}},
		"choices": {"t": "array", "min": 2, "max": 3, "lenient": true, "items": {"t": "object", "fields": {
			"text": {"t": "string", "min": 5, "max": 140},
			"consequence": {"t": "enum", "from": "awakening_consequence", "default": ""},
		}}},
		"destination_hint": {"t": "string", "min": 10, "max": 300, "default": "Un lugar en otra rama del multiverso."},
	},
	# Misión local. El motor resuelve target_index contra las listas reales del lugar
	# (puntos de interés, PNJs u objetos), así la IA no puede inventar objetivos imposibles.
	"quest": {
		"title": {"t": "string", "min": 3, "max": 60},
		"description": {"t": "string", "min": 10, "max": 300},
		"objective": {"t": "enum", "from": "quest_objective", "default": "visit_poi"},
		"target_index": {"t": "int", "min": 0, "max": 5, "default": 0},
		"completion_text": {"t": "string", "min": 5, "max": 300},
	},
	# El origen de la señal: revelación final y los tres finales con su epílogo.
	"finale": {
		"title": {"t": "string", "min": 2, "max": 60},
		"revelation": {"t": "string", "min": 80, "max": 1500},
		"source_voice": {"t": "string", "min": 10, "max": 400},
		"choices": {"t": "array", "min": 3, "max": 3, "lenient": true, "items": {"t": "object", "fields": {
			"text": {"t": "string", "min": 5, "max": 140},
			"ending": {"t": "enum", "from": "ending", "default": ""},
			"epilogue": {"t": "string", "min": 40, "max": 900},
		}}},
	},
}

## Tipos que se guardan en WorldDB (el resto de SPECS son respuestas efímeras).
const ENTITY_TYPES := ["npc", "location", "item"]

## Traducciones habituales que hacen los modelos al escribir en español.
const SYNONYMS := {
	"neutro": "neutral", "neutra": "neutral", "feliz": "happy", "alegre": "happy", "contento": "happy",
	"contenta": "happy", "animado": "happy", "animada": "happy", "entusiasmado": "happy", "triste": "sad",
	"preocupado": "worried", "preocupada": "worried", "nervioso": "worried", "nerviosa": "worried",
	"enfadado": "angry", "enfadada": "angry", "enojado": "angry", "enojada": "angry", "curioso": "curious",
	"curiosa": "curious", "intrigado": "curious", "intrigada": "curious", "asustado": "scared",
	"asustada": "scared", "divertido": "amused", "divertida": "amused", "bromista": "amused",
	"misterioso": "mysterious", "misteriosa": "mysterious", "enigmático": "mysterious",
	"amigable": "friendly", "amistoso": "friendly", "cordial": "friendly", "honesto": "honest",
	"sincero": "honest", "directo": "honest", "evasivo": "evasive", "audaz": "bold", "atrevido": "bold",
	"valiente": "bold", "amable": "kind", "frío": "cold", "frio": "cold", "sarcástico": "sarcastic",
	"sarcastico": "sarcastic", "irónico": "sarcastic", "curiosidad": "curiosity", "empatía": "empathy",
	"empatia": "empathy", "valentía": "courage", "valentia": "courage", "coraje": "courage",
	"escepticismo": "skepticism", "escéptico": "skepticism", "ambición": "ambition", "ambicion": "ambition",
	"dar": "give_item", "dar_objeto": "give_item", "prestar": "give_item", "entregar": "give_item",
	"regalar": "give_item", "lend_item": "give_item", "lend": "give_item", "recibir": "take_item",
	"recibir_objeto": "take_item", "tomar": "take_item", "coger": "take_item", "receive_item": "take_item",
	"seguir": "follow_player", "seguir_jugador": "follow_player", "acompañar": "follow_player",
	"follow": "follow_player", "accompany": "follow_player", "dejar_de_seguir": "stop_following",
	"ir_a": "go_to", "ir": "go_to", "move_to": "go_to", "curar": "change_stat", "heal": "change_stat",
	"revelar_lugar": "reveal_place", "dar_mision": "give_quest", "misión": "give_quest", "mision": "give_quest",
	"completar_mision": "complete_quest", "negarse": "refuse_contact", "diario": "journal", "nota": "journal",
	"pista": "journal", "salud": "health", "vida": "health", "energía": "energy", "energia": "energy",
	"inestabilidad": "instability", "reparar": "update_item", "arreglar": "update_item", "modificar": "update_item",
	"mejorar": "update_item", "modify_item": "update_item", "repair_item": "update_item", "gastar": "remove_item",
	"consumir": "remove_item", "consume_item": "remove_item", "use_item": "remove_item", "destroy_item": "remove_item",
	"construir": "place_object", "colocar": "place_object", "fabricar": "place_object", "build": "place_object",
	"build_object": "place_object", "craft": "place_object", "spawn_object": "place_object", "talar": "affect_nearby",
	"cortar": "affect_nearby", "romper": "affect_nearby", "cosechar": "affect_nearby", "chop_tree": "affect_nearby",
	"gesto": "play", "animación": "play", "animacion": "play", "animation": "play", "gesture": "play", "emote": "play",
	"bote": "boat", "barca": "boat", "barco": "boat", "canoa": "boat", "balsa": "raft", "hoguera": "campfire",
	"fogata": "campfire", "fuego": "campfire", "tienda": "tent", "carpa": "tent", "refugio": "shelter", "cabaña": "shelter",
	"mesa": "table", "silla": "chair", "banco": "chair", "cama": "bed", "valla": "fence", "cerca": "fence",
	"cartel": "sign", "letrero": "sign", "antorcha": "torch", "caja": "box", "cofre": "box", "huerto": "garden",
	"árbol": "tree", "arbol": "tree", "roca": "rock", "piedra": "rock", "arbusto": "bush", "cultivo": "crop",
	"saludar": "wave", "señalar": "point", "sentarse": "sit", "dormir": "sleep", "beber": "drink", "comer": "eat",
	"pensar": "think", "bailar": "dance", "pescar": "fish", "remar": "row", "nadar": "swim", "excavar": "dig", "cavar": "dig",
	"recoger": "pick_up", "buscar": "search", "agacharse": "crouch", "martillar": "hammer", "asentir": "nod",
	"negar": "shake_head", "encogerse_de_hombros": "shrug", "cruzar_brazos": "cross_arms", "entregar_objeto": "give", "masculino": "masculine", "hombre": "masculine", "male": "masculine",
	"femenino": "feminine", "mujer": "feminine", "female": "feminine",
	"irse": "leave", "marcharse": "leave", "salir": "leave", "go_away": "leave", "walk_away": "leave", "exit": "leave",
	"entrar": "go_inside", "encerrarse": "go_inside", "meterse": "go_inside", "enter": "go_inside", "enter_building": "go_inside",
	"go_home": "go_inside", "acercarse": "approach", "approach_player": "approach", "reaccionar": "npc_react",
	"reaction": "npc_react", "react": "npc_react", "dar_a": "give_to_npc", "give_to": "give_to_npc", "hand_over": "give_to_npc",
	"usar": "use", "use_object": "use", "interact": "use", "interactuar": "use", "ir_hasta": "go_to", "caminar": "go_to",
	"walk_to": "go_to", "golpear": "punch", "pegar": "punch", "puñetazo": "punch", "hit": "punch", "strike": "punch",
	"empujar": "push", "patear": "kick", "patada": "kick", "abrazar": "hug", "abrazo": "hug", "dar_la_mano": "handshake",
	"saludar_mano": "handshake", "lanzar": "throw", "tirar": "throw", "palmada": "pat", "arrodillarse": "kneel",
	"escribir": "write", "anotar": "write", "leer": "read", "escuchar": "listen", "llamar": "call", "telefonear": "call",
	"huir": "flee", "escapar": "flee", "run_away": "flee", "quedarse": "stay", "defenderse": "fight_back",
	"devolver_golpe": "fight_back", "fight": "fight_back",
	"dar_numero": "share_number", "dar_número": "share_number", "give_number": "share_number", "share_phone": "share_number",
	"contratar": "hire_player", "hire": "hire_player", "offer_job": "hire_player", "dar_trabajo": "hire_player", "emplear": "hire_player",
	"despedir": "quit_job", "renunciar": "quit_job", "fire_player": "quit_job", "quit": "quit_job",
	"luz": "light", "linterna": "light", "lamp": "light", "comer_item": "nourish", "food_item": "nourish", "edible": "nourish",
	"beber_item": "hydrate", "drinkable": "hydrate", "telefono": "phone", "teléfono": "phone", "celular": "phone",
	"radio": "signal", "receptor": "signal", "abrigo": "warmth", "warm": "warmth", "herramienta": "tool",
	"asiento": "seat", "refugio_lluvia": "shelter", "calor": "heat", "calefacción": "heat", "almacén": "storage", "baúl": "storage",
	"guardar": "storage", "chest": "storage", "antena": "signal", "cubo": "box", "caja_forma": "box", "cilindro": "cylinder",
	"esfera": "sphere", "bola": "sphere",
	"hambre": "hunger", "comida": "hunger", "food": "hunger", "sed": "thirst", "bebida": "thirst", "water": "thirst",
	"descanso": "rest", "sueño": "rest", "cansancio": "rest", "sleep_need": "rest", "fatigue": "rest", "higiene": "hygiene",
	"limpieza": "hygiene", "ducha": "hygiene", "cleanliness": "hygiene", "necesidad": "change_need", "satisfy_need": "change_need",
	"comer_beber": "change_need", "pagar": "pay", "payment": "pay", "spend": "pay", "gastar_dinero": "pay", "cobrar": "charge",
	"cobrarle": "charge", "sell": "charge", "vender": "charge", "charge_player": "charge", "ganar": "earn", "ganar_dinero": "earn",
	"cobrar_trabajo": "earn", "get_paid": "earn", "receive_money": "earn", "pagar_jugador": "pay_player", "pay_to_player": "pay_player",
	"dar_dinero": "pay_player", "give_money": "pay_player", "crear_persona": "spawn_npc", "aparece": "spawn_npc", "create_npc": "spawn_npc",
	"new_npc": "spawn_npc", "add_npc": "spawn_npc", "llamar_a": "spawn_npc", "crear_lugar": "create_place", "crear_sitio": "create_place",
	"new_place": "create_place", "add_place": "create_place", "build_place": "create_place", "abrir_negocio": "create_place",
	"store": "shop", "comercio": "shop", "panadería": "bakery", "panaderia": "bakery", "horno": "bakery", "bakery_shop": "bakery",
	"taberna": "bar", "pub": "bar", "restaurante": "bar", "restaurant": "bar", "taller_mecánico": "workshop", "garage": "workshop",
	"oficina": "office", "consulta": "clinic", "clínica": "clinic", "clinica": "clinic", "médico": "clinic", "farmacia": "clinic",
	"mercado": "market", "puesto": "market", "pescadería": "market", "pescaderia": "market", "limpiar": "wipe", "fregar": "wipe",
}

var _archetypes: Dictionary = {}


func types() -> Array:
	return ENTITY_TYPES


func archetypes() -> Dictionary:
	if _archetypes.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(ARCHETYPES_PATH))
		if typeof(parsed) == TYPE_DICTIONARY:
			parsed.erase("_comment")
			_archetypes = parsed
	return _archetypes


## Devuelve { ok, data (normalizada y reparada), errors: [String], warnings: [String] }.
## errors: falta algo esencial → la respuesta no sirve. warnings: detalles reparados.
func validate(type: String, data: Variant) -> Dictionary:
	if not SPECS.has(type):
		return {"ok": false, "data": null, "errors": ["Tipo desconocido: %s" % type], "warnings": []}
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var clean = _check({"t": "object", "fields": SPECS[type]}, data, type, errors, warnings)
	return {"ok": errors.is_empty(), "data": clean, "errors": errors, "warnings": warnings}


func to_json_schema(type: String) -> Dictionary:
	return _schema({"t": "object", "fields": SPECS[type]})


## Descripción legible del formato para el prompt: los modelos que no respetan "format"
## sí suelen respetar una lista explícita de claves y valores permitidos.
func describe_format(type: String) -> String:
	var lines := PackedStringArray()
	for key in SPECS[type]:
		lines.append("- \"%s\": %s" % [key, _describe(SPECS[type][key])])
	return "\n".join(lines)


func _describe(spec: Dictionary) -> String:
	var opt := " (opcional)" if spec.get("opt", false) else ""
	match spec.t:
		"string":
			return "texto en español" + opt
		"int":
			return "número entero entre %d y %d%s" % [spec.min, spec.max, opt]
		"float":
			return "número entre %s y %s%s" % [spec.min, spec.max, opt]
		"bool":
			return "true o false" + opt
		"color":
			return "color hexadecimal \"#rrggbb\"" + opt
		"enum":
			return "EXACTAMENTE uno de %s (en inglés, tal cual)%s" % [JSON.stringify(archetypes().get(spec.from, [])), opt]
		"array":
			return "lista de %d a %d elementos; cada uno: %s%s" % [spec.min, spec.max, _describe(spec.items), opt]
		"object":
			var parts := PackedStringArray()
			for k in spec.fields:
				parts.append("\"%s\": %s" % [k, _describe(spec.fields[k])])
			return "objeto { %s }%s" % [", ".join(parts), opt]
	return ""


func _check(spec: Dictionary, value: Variant, path: String, errors: Array[String], warnings: Array[String]) -> Variant:
	match spec.t:
		"string":
			if typeof(value) != TYPE_STRING:
				if value == null or typeof(value) == TYPE_DICTIONARY or typeof(value) == TYPE_ARRAY:
					return _fallback(spec, path, "se esperaba texto", errors, warnings)
				value = str(value)
			var s: String = value.strip_edges()
			if s.length() < spec.get("min", 0):
				return _fallback(spec, path, "texto demasiado corto", errors, warnings)
			return s.left(spec.get("max", 10000))
		"int", "float":
			if typeof(value) == TYPE_STRING and (value as String).is_valid_float():
				value = (value as String).to_float()
			if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
				return _fallback(spec, path, "se esperaba un número", errors, warnings)
			var n = clampf(float(value), spec.min, spec.max)
			return roundi(n) if spec.t == "int" else n
		"bool":
			if typeof(value) == TYPE_STRING:
				value = (value as String).to_lower() in ["true", "sí", "si", "yes"]
			if typeof(value) != TYPE_BOOL:
				return _fallback(spec, path, "se esperaba true/false", errors, warnings)
			return value
		"color":
			if typeof(value) != TYPE_STRING or not Color.html_is_valid(value):
				return _fallback(spec, path, "color inválido (usa #rrggbb)", errors, warnings)
			return "#" + Color.html(value).to_html(false)
		"enum":
			var allowed: Array = archetypes().get(spec.from, [])
			var matched := _match_enum(value, allowed)
			if matched.is_empty():
				return _fallback(spec, path, "'%s' no es válido, usa uno de %s" % [value, allowed], errors, warnings)
			if matched != str(value):
				warnings.append("%s: '%s' → '%s'" % [path, value, matched])
			return matched
		"array":
			if typeof(value) != TYPE_ARRAY:
				if spec.get("opt", false) and not spec.has("default"):
					return []
				return _fallback(spec, path, "se esperaba una lista", errors, warnings)
			var out := []
			for i in value.size():
				if out.size() >= spec.max:
					break
				var item_errors: Array[String] = []
				var item = _check(spec.items, value[i], "%s[%d]" % [path, i], item_errors, warnings)
				if item_errors.is_empty():
					out.append(item)
				elif spec.get("lenient", false):
					warnings.append("%s[%d] descartado: %s" % [path, i, "; ".join(item_errors)])
				else:
					errors.append_array(item_errors)
			if out.size() < spec.min:
				if spec.has("default"):
					warnings.append("%s: pocos elementos válidos, se usa el valor por defecto" % path)
					return _default_of(spec)
				errors.append("%s: se necesitan al menos %d elementos válidos" % [path, spec.min])
			return out
		"object":
			# Muchos modelos devuelven "opción" como texto en lugar de {"text": "opción", ...}
			if typeof(value) == TYPE_STRING and spec.fields.has("text"):
				value = {"text": value}
			if typeof(value) != TYPE_DICTIONARY:
				return _fallback(spec, path, "se esperaba un objeto", errors, warnings)
			var out := {}
			for key in spec.fields:
				var field: Dictionary = spec.fields[key]
				if not value.has(key) or value[key] == null:
					if field.has("default"):
						out[key] = _default_of(field)
						warnings.append("%s.%s: falta, se usa el valor por defecto" % [path, key])
					elif not field.get("opt", false):
						errors.append("%s.%s: falta" % [path, key])
					continue
				out[key] = _check(field, value[key], "%s.%s" % [path, key], errors, warnings)
			return out  # las claves desconocidas se descartan a propósito
	errors.append("%s: spec con tipo desconocido '%s'" % [path, spec.t])
	return null


## Un valor inválido: si el campo tiene "default" se repara (aviso); si no, es un error.
func _fallback(spec: Dictionary, path: String, msg: String, errors: Array[String], warnings: Array[String]) -> Variant:
	if spec.has("default"):
		warnings.append("%s: %s (se usa el valor por defecto)" % [path, msg])
		return _default_of(spec)
	errors.append("%s: %s" % [path, msg])
	return null


## Para objetos con default {} se construye el objeto con los defaults de sus campos.
func _default_of(spec: Dictionary) -> Variant:
	if spec.t == "object":
		var out := {}
		for k in spec.fields:
			out[k] = _default_of(spec.fields[k]) if spec.fields[k].has("default") else null
		return out
	var d = spec.default
	return d.duplicate(true) if d is Dictionary or d is Array else d


## Acepta el valor exacto, mayúsculas/espacios distintos, sinónimos en español o un prefijo claro.
func _match_enum(value: Variant, allowed: Array) -> String:
	if typeof(value) != TYPE_STRING:
		return ""
	if value in allowed:
		return value
	var v: String = (value as String).strip_edges().to_lower().replace(" ", "_").replace("-", "_")
	if v in allowed:
		return v
	var syn: String = SYNONYMS.get(v, "")
	if syn in allowed:
		return syn
	for a in allowed:
		if v.begins_with(a) or (a.length() >= 4 and a.begins_with(v) and v.length() >= 4):
			return a
	return ""


func _schema(spec: Dictionary) -> Dictionary:
	match spec.t:
		"string":
			return {"type": "string"}
		"color":
			return {"type": "string", "pattern": "^#[0-9a-fA-F]{6}$"}
		"int":
			return {"type": "integer", "minimum": spec.min, "maximum": spec.max}
		"float":
			return {"type": "number", "minimum": spec.min, "maximum": spec.max}
		"bool":
			return {"type": "boolean"}
		"enum":
			return {"type": "string", "enum": archetypes().get(spec.from, [])}
		"array":
			return {"type": "array", "items": _schema(spec.items), "minItems": spec.min, "maxItems": spec.max}
		"object":
			var props := {}
			var required := []
			for key in spec.fields:
				props[key] = _schema(spec.fields[key])
				if not spec.fields[key].get("opt", false):
					required.append(key)
			return {"type": "object", "properties": props, "required": required}
	return {}
