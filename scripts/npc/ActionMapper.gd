class_name ActionMapper
extends RefCounted
## Lo que un PNJ narra que hace («Da un sorbo al café y señala el faro») se convierte en pasos que
## su cuerpo hace de verdad: gestos, mirar hacia algo, dar unos pasos. Una frase que no se puede
## hacer en el juego no se muestra: nada de acotaciones que no pasan.
##
## Pasos: {type: "gesture", gesture} · {type: "face", target} · {type: "walk", target}
##        · {type: "emotion", emotion} · {type: "wear"/"remove", garment}

## [palabras, gesto]. El orden importa: lo más concreto primero.
const GESTURES := [
	[["niega con la cabeza", "sacude la cabeza", "mueve la cabeza de lado"], "shake_head"],
	[["asiente", "afirma con la cabeza"], "nod"],
	[["se encoge de hombros", "encoge los hombros"], "shrug"],
	[["cruza los brazos", "se cruza de brazos", "brazos cruzados"], "cross_arms"],
	[["sorbo", "bebe", "trago", "da un trago", "toma un poco de"], "drink"],
	[["muerde", "mordisco", "come ", "se come", "mastica"], "eat"],
	[["señala", "apunta hacia", "apunta con el dedo", "indica con la mano", "con un gesto hacia"], "point"],
	[["saluda", "agita la mano", "levanta la mano"], "wave"],
	[["bosteza", "se despereza"], "yawn"],
	[["se rasca la barbilla", "pensativ", "se queda pensando", "reflexiona", "frunce el ceño pensando"], "think"],
	[["limpia", "pasa un trapo", "seca la barra", "seca un vaso", "frota"], "wipe"],
	[["cocina", "remueve la olla", "prepara la comida", "sirve un café", "prepara un café", "prepara el café"], "cook"],
	[["escribe", "anota", "apunta en"], "write"],
	[["lee", "hojea", "repasa unos papeles"], "read"],
	[["mira el celular", "revisa el celular", "llama por teléfono", "marca un número", "contesta el teléfono"], "call"],
	[["abraza", "le da un abrazo"], "hug"],
	[["estrecha la mano", "te da la mano", "le da la mano", "tiende la mano"], "handshake"],
	[["palmada", "palmea", "da unas palmaditas", "te toca el hombro", "le toca el hombro"], "pat"],
	[["se agacha", "se pone en cuclillas"], "crouch"],
	[["se arrodilla", "se pone de rodillas"], "kneel"],
	[["se sienta", "toma asiento"], "sit"],
	[["martill", "golpea con el martillo", " repara", "arregla la", "arregla el", "ajusta un tornillo", "aprieta"], "hammer"],
	[["busca", "rebusca", "hurga"], "search"],
	[["escucha atent", "presta atención", "ladea la cabeza"], "listen"],
	[["empuja"], "push"],
	[["llama a la puerta", "toca la puerta"], "knock"],
	[["se ajusta", "se abrocha", "se sube el cuello", "se acomoda", "se arregla el", "se arregla la", "se quita el polvo"], "pat"],
]
## Expresiones de la cara: se ven aunque no haya gesto.
const FACES := {"sonríe": "happy", "se ríe": "amused", "ríe": "amused", "suelta una risa": "amused", "frunce el ceño": "angry",
	"suspira": "sad", "baja la mirada": "sad", "abre mucho los ojos": "surprised", "se sorprende": "surprised",
	"traga saliva": "scared", "se pone pálid": "scared", "se sonroja": "happy", "pone los ojos en blanco": "amused"}
## Mirar hacia algo.
const LOOK := ["mira hacia", "mira al ", "mira a la ", "mira por", "se asoma", "echa un vistazo", "voltea hacia", "se gira hacia",
	"observa", "contempla", "mira de reojo", "te mira", "le mira", "mira al jugador"]
## Dar unos pasos hacia algo.
const WALK := ["se acerca a", "camina hacia", "va hacia", "se dirige a", "da unos pasos hacia", "se aproxima a", "se mueve hacia"]
const WEAR := ["se pone el", "se pone la", "se pone los", "se coloca el", "se coloca la"]
const REMOVE := ["se quita el", "se quita la", "se quita los"]
## Subirse o bajarse de un vehículo (si hay uno cerca: si no, la frase no se muestra).
const RIDE := ["se sube al coche", "se sube al auto", "se sube al carro", "se sube a la camioneta", "se sube a la furgoneta",
	"se monta en el", "se monta en la", "se sienta en el asiento del copiloto", "sube al coche", "sube al auto", "se sube al asiento"]
## «se sube a tu coche», «se sube a la moto», «se sienta atrás», «sube a la nave»…
## (Se crea cada vez: un RegEx en una variable estática puede fallar al cerrar el juego.)
static func _ride_re() -> RegEx:
	return RegEx.create_from_string("(se sube|sube|se monta|se mete|se acomoda|se sienta)( contigo)? (a|al|en|en el|en la|a la|a tu|en tu)( [a-záéíóúñ]+)? (coche|auto|carro|camioneta|furgoneta|moto|nave|lancha|bote|barca|veh[ií]culo|sed[aá]n|taxi|pickup|copiloto)|(se sienta|se sube) atr[aá]s")
const GET_OUT := ["se baja del coche", "se baja del auto", "se baja del carro", "se baja de la camioneta", "baja del coche", "sale del coche"]


## Traduce una acotación a pasos. `known`: nombres de cosas y sitios que existen (para mirar o
## caminar hacia ellos). Devuelve {steps, shown}: `shown` es la acotación con solo las frases que
## de verdad se van a ver.
static func map(action: String, known: Array = []) -> Dictionary:
	var steps := []
	var shown := PackedStringArray()
	for sentence in StoryDirector._sentences(action):
		var s := _sentence(sentence, known)
		if s.is_empty():
			continue
		steps.append_array(s)
		shown.append(sentence)
	return {"steps": steps, "shown": " ".join(shown)}


static func _sentence(sentence: String, known: Array) -> Array:
	var low := " " + sentence.to_lower() + " "
	var out := []
	var garment := Wardrobe.find(low)
	if not garment.is_empty():
		if WEAR.any(func(w): return low.contains(w)):
			out.append({"type": "wear", "garment": garment})
		elif REMOVE.any(func(w): return low.contains(w)):
			out.append({"type": "remove", "garment": garment})
	if RIDE.any(func(w): return low.contains(w)) or _ride_re().search(low) != null:
		out.append({"type": "ride"})
	elif GET_OUT.any(func(w): return low.contains(w)):
		out.append({"type": "get_out"})
	for w in WALK:
		var i := low.find(w)
		if i >= 0:
			var t := _known_in(low.substr(i + w.length()), known)
			if not t.is_empty():
				out.append({"type": "walk", "target": t})
			break
	for w in LOOK:
		var i := low.find(w)
		if i >= 0:
			var rest := low.substr(i + w.length())
			var t := "player" if w in ["te mira", "le mira", "mira al jugador"] or rest.begins_with(" ti") else _known_in(rest, known)
			out.append({"type": "face", "target": t if not t.is_empty() else "away"})
			break
	for g in GESTURES:
		if g[0].any(func(w): return low.contains(w)):
			var step := {"type": "gesture", "gesture": g[1]}
			if g[1] == "point":
				var t := _known_in(low, known)
				if not t.is_empty():
					out.append({"type": "face", "target": t})
			out.append(step)
			break
	for f in FACES:
		if low.contains(f):
			out.append({"type": "emotion", "emotion": FACES[f]})
			break
	return out


## El nombre conocido (sitio, cosa) que aparece en `text`, el más largo; "" si ninguno.
static func _known_in(text: String, known: Array) -> String:
	var best := ""
	for k in known:
		var name := str(k).to_lower()
		if name.length() >= 3 and text.contains(name) and name.length() > best.length():
			best = str(k)
	return best
