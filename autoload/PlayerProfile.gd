extends Node
## Quién es el jugador, inferido de cómo juega. Alimenta todos los prompts:
## a un jugador curioso el mundo le ofrece misterios; a uno empático, personas que ayudar.

signal changed

const TRAITS := ["curiosity", "empathy", "courage", "skepticism", "ambition"]
const LABELS := {
	"curiosity": ["indiferente", "curioso/a"],
	"empathy": ["frío/a", "empático/a"],
	"courage": ["prudente", "valiente"],
	"skepticism": ["crédulo/a", "escéptico/a"],
	"ambition": ["conformista", "ambicioso/a"],
}
const LIMIT := 50


func get_profile() -> Dictionary:
	var p: Dictionary = WorldDB.get_state("profile", {})
	if p.is_empty():
		p = {"name": "", "traits": {}, "decisions": 0}
		for t in TRAITS:
			p.traits[t] = 0
	return p


func set_player_name(player_name: String) -> void:
	var p := get_profile()
	p.name = player_name
	WorldDB.set_state("profile", p)
	changed.emit()


func player_name() -> String:
	var n: String = get_profile().name
	return n if not n.is_empty() else "la persona protagonista"


## signals: [{trait, delta}] validados por ContentValidator.
func apply_signals(signals: Array) -> void:
	var p := get_profile()
	p.decisions += 1
	for s in signals:
		var t: String = s.get("trait", "")  # s["trait"]: "trait" podría ser palabra reservada en el futuro
		if t in TRAITS:
			# int(): tras cargar de JSON todos los números llegan como float
			p.traits[t] = clampi(int(p.traits[t]) + int(s.get("delta", 0)), -LIMIT, LIMIT)
	WorldDB.set_state("profile", p)
	changed.emit()


## Texto para el prompt. Solo menciona rasgos marcados para no inventar personalidad.
func describe() -> String:
	var p := get_profile()
	var parts: PackedStringArray = []
	for t in TRAITS:
		var v := int(p.traits[t])
		if absi(v) >= 3:
			parts.append("%s (%+d)" % [LABELS[t][1 if v > 0 else 0], v])
	var traits := "aún no se sabe mucho de su carácter" if parts.is_empty() else ", ".join(parts)
	return "%s. Carácter observado: %s. Decisiones tomadas: %d." % [player_name(), traits, int(p.decisions)]
