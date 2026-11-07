class_name NavBaker
extends RefCounted
## Malla de navegación de una zona (el pueblo, un interior): sale de los colisionadores del mundo
## (paredes, muebles, árboles, bancas) y se hornea en un hilo aparte. Con ella los PNJ buscan un
## camino que rodea lo que hay en medio en vez de ir en línea recta y chocar.

const AGENT_RADIUS := 0.25  # múltiplos de la celda (0.25 × 0.2): si no, Godot redondea y avisa
                            # (con 0.5 no cabían por el paso tras la barra ni entre mesas)
const AGENT_HEIGHT := 1.8


## Hornea la zona `area` (en coordenadas del mundo) a partir de lo que cuelga de `root`.
## Devuelve la región (ya en el árbol; la malla llega cuando termina el hilo). `now`: hornear en el
## momento (un interior es pequeño y se borra al salir: en un hilo podría morir a medio hornear).
static func bake(root: Node3D, area: AABB, name: String = "Navegacion", now: bool = false) -> NavigationRegion3D:
	var mesh := NavigationMesh.new()
	mesh.agent_radius = AGENT_RADIUS
	mesh.agent_height = AGENT_HEIGHT
	mesh.agent_max_climb = 0.4
	mesh.agent_max_slope = 40.0
	mesh.cell_size = 0.25
	mesh.cell_height = 0.2
	mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	mesh.geometry_collision_mask = Layers.WORLD
	mesh.filter_baking_aabb = area
	var region := NavigationRegion3D.new()
	region.name = name
	region.navigation_mesh = mesh
	root.add_child(region)
	# La celda del mapa tiene que coincidir con la de la malla (si no, Godot avisa y no enlaza)
	NavigationServer3D.map_set_cell_size(root.get_world_3d().navigation_map, mesh.cell_size)
	NavigationServer3D.map_set_cell_height(root.get_world_3d().navigation_map, mesh.cell_height)
	var source := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(mesh, source, root)
	if now:
		NavigationServer3D.bake_from_source_geometry_data(mesh, source)
		region.navigation_mesh = mesh
		region.set_meta("baked", true)
		return region
	NavigationServer3D.bake_from_source_geometry_data_async(mesh, source, func():
		if is_instance_valid(region):
			region.navigation_mesh = mesh  # vuelve a asignarla para que el servidor la recoja ya horneada
			region.set_meta("baked", true))
	return region


## El punto de la malla más cercano a `to` (para no apuntar dentro de un mueble), o `to` si no hay.
static func closest(node: Node3D, to: Vector3) -> Vector3:
	if not ready_for(node):
		return to
	var p := NavigationServer3D.map_get_closest_point(node.get_world_3d().navigation_map, to)
	return p if p.distance_to(to) < 1.6 else to


## ¿Hay malla en el mapa de este nodo? (antes de hornear, o en una escena sin ella, se va recto).
static func ready_for(node: Node3D) -> bool:
	if not node.is_inside_tree():
		return false
	return NavigationServer3D.map_get_iteration_id(node.get_world_3d().navigation_map) > 0 \
		and not NavigationServer3D.map_get_regions(node.get_world_3d().navigation_map).is_empty()


## Camino de `from` a `to` por la malla (vacío si no hay malla o no hay camino).
static func path(node: Node3D, from: Vector3, to: Vector3) -> PackedVector3Array:
	if not ready_for(node):
		return PackedVector3Array()
	var map := node.get_world_3d().navigation_map
	var p := NavigationServer3D.map_get_path(map, from, to, true)
	if p.size() < 2:
		return PackedVector3Array()
	# Si la malla no llega cerca del destino (dentro de algo, al otro lado del agua), no sirve
	if Vector2(p[-1].x - to.x, p[-1].z - to.z).length() > 3.0:
		return PackedVector3Array()
	return p
