extends SceneTree
## Que todo se vea en cualquier pantalla: abre cada panel (ajustes, pausa con controles, celular,
## Cuaderno, diálogo, baúl, barra de F) con ventanas de distintos tamaños y comprueba que sus
## paneles quedan dentro de la pantalla.
##   godot --headless --path . -s tests/test_layout.gd

const SIZES := [Vector2i(1024, 576), Vector2i(1280, 650), Vector2i(1366, 705), Vector2i(1920, 1080)]

var _failed := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var db = root.get_node("/root/WorldDB")
	var settings = root.get_node("/root/Settings")
	settings.use_mock = true
	var previous_last: String = db.last_world_id()
	var world_id: String = db.create_world("Prueba de pantalla")
	for entry in JSON.parse_string(FileAccess.get_file_as_string("res://data/act0/npcs.json")):
		db.add_entity("npc", entry.entity, "act0:base", entry.id)
	root.get_node("/root/Phone").ensure_phone()
	var actions = root.get_node("/root/Actions")
	actions.execute("", [{"type": "give_item", "item_name": "Hacha vieja"}, {"type": "give_item", "item_name": "Radio de onda corta"}])

	for size in SIZES:
		root.size = size
		for i in 3:
			await process_frame
		var screen: Rect2 = root.get_visible_rect()
		var checks := {
			"ajustes": func(): var p = load("res://scenes/ui/SettingsPanel.gd").new(); root.add_child(p); return p,
			"pausa + controles": func():
				var p = load("res://scenes/ui/PauseMenu.gd").new(); root.add_child(p); p.open(); p._toggle_controls(); return p,
			"celular": func():
				var p = load("res://scenes/ui/PhonePanel.gd").new(); root.add_child(p); p.open(); return p,
			"cuaderno": func():
				var p = load("res://scenes/ui/InventoryPanel.gd").new(); root.add_child(p); p.open(); return p,
			"diálogo": func():
				var p = load("res://scenes/ui/DialoguePanel.gd").new(); root.add_child(p); p.open("npc_teo"); return p,
			"baúl": func():
				var p = load("res://scenes/ui/StashPanel.gd").new(); root.add_child(p); p.open("x", "Baúl"); return p,
			"barra de F": func():
				var p = load("res://scenes/ui/ActionPanel.gd").new(); root.add_child(p); p.open("Talo el árbol"); return p,
		}
		for name in checks:
			var panel: Node = checks[name].call()
			for i in 6:
				await process_frame
			var out := _outside(panel, screen)
			_expect(out.is_empty(), "%dx%d · %s dentro de la pantalla %s" % [size.x, size.y, name, out])
			panel.queue_free()
			await process_frame

	settings.use_mock = false
	db.delete_world(world_id)
	db.set_last_world_id(previous_last)
	print("\n%s" % ("TODO OK" if _failed == 0 else "%d FALLOS" % _failed))
	quit(_failed)


## Paneles visibles que se salen de la pantalla (con 2 px de margen).
func _outside(node: Node, screen: Rect2) -> Array:
	var out := []
	for c in node.find_children("*", "PanelContainer", true, false):
		var ctrl := c as Control
		if not ctrl.is_visible_in_tree() or ctrl.size == Vector2.ZERO or _scrolled(ctrl):
			continue  # dentro de una lista desplazable se ve al desplazar: cuenta la lista, no cada fila
		var r := ctrl.get_global_rect()
		if r.position.x < screen.position.x - 2 or r.position.y < screen.position.y - 2 or r.end.x > screen.end.x + 2 or r.end.y > screen.end.y + 2:
			out.append("%s %s" % [ctrl.name, r])
	return out.slice(0, 3)


func _scrolled(c: Node) -> bool:
	var p := c.get_parent()
	while p != null:
		if p is ScrollContainer:
			return true
		p = p.get_parent()
	return false


func _expect(cond: bool, msg: String) -> void:
	print(("  ✔ " if cond else "  ✘ ") + msg)
	if not cond:
		_failed += 1
