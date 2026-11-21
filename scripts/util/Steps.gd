class_name Steps
extends RefCounted
## Subir un escalón andando, sin saltar (el jugador y los vecinos): un bordillo, un peldaño, la
## tarima del embarcadero. Antes se miraba a 0.30 m del centro con una cápsula de 0.32 de radio:
## el borde de algo más alto que ~21 cm quedaba más lejos y el escalón te frenaba en seco, como
## una pared invisible.

## Sube `body` a lo que tiene delante si es un escalón de hasta `max_h` (m). `dir`: hacia dónde
## quiere ir. `radius`: el de su cápsula. Devuelve cuánto subió (0 si no era un escalón).
static func try_step(body: CharacterBody3D, dir: Vector3, radius: float, max_h: float) -> float:
	if not body.is_on_floor() or not body.is_on_wall() or dir == Vector3.ZERO:
		return 0.0
	var fwd := Vector3(dir.x, 0, dir.z).normalized()
	# Hacia el escalón: la normal de la pared manda si vas casi de frente; en diagonal, tu dirección
	var wall := -body.get_wall_normal()
	wall.y = 0.0
	if wall.length() > 0.1 and wall.normalized().dot(fwd) > 0.35:
		fwd = wall.normalized()
	elif fwd.dot(wall.normalized()) <= 0.0:
		return 0.0  # la pared queda detrás o al lado: no vas hacia ella
	var raised := body.global_transform.translated(Vector3(0, max_h + 0.02, 0))
	if body.test_move(raised, fwd * 0.25):
		return 0.0  # sigue chocando aun subiendo: es una pared, no un escalón
	var side := fwd.cross(Vector3.UP).normalized()
	var space := body.get_world_3d().direct_space_state
	var rise := 0.0
	for lateral in [0.0, -0.15, 0.15]:
		var at: Vector3 = body.global_position + fwd * (radius + 0.06) + side * lateral
		var q := PhysicsRayQueryParameters3D.create(at + Vector3(0, max_h + 0.05, 0), at - Vector3(0, 0.05, 0),
			body.collision_mask & Layers.WORLD, [body.get_rid()])
		var hit := space.intersect_ray(q)
		if hit.is_empty() or (hit.normal as Vector3).y < 0.7:
			continue
		var r: float = hit.position.y - body.global_position.y
		if r > 0.02 and r <= max_h:
			rise = maxf(rise, r)
	if rise <= 0.0:
		return 0.0
	body.global_position += Vector3(0, rise + 0.02, 0) + fwd * 0.12
	body.velocity.y = maxf(body.velocity.y, 0.0)
	return rise
