class_name Layers
## Capas de física (nombradas en project.godot → layer_names/3d_physics).
##   1 mundo: suelo, paredes, muebles, árboles, barcas. Tapan la vista y la cámara choca con ellas.
##   2 personajes: jugador y PNJs. Chocan con el mundo y entre sí, pero no tapan la cámara.

const WORLD := 1
const CHARACTERS := 2


## Un cuerpo de personaje: está en "personajes" y choca con el mundo y con otros personajes.
static func character(body: CollisionObject3D) -> void:
	body.collision_layer = CHARACTERS
	body.collision_mask = WORLD | CHARACTERS


## Una zona que detecta personajes (no ocupa ninguna capa).
static func zone(area: Area3D) -> void:
	area.collision_layer = 0
	area.collision_mask = CHARACTERS
