extends SceneTree
## Abre una escena, la deja correr unos fotogramas y cierra el juego como lo hace el jugador (en
## orden: Sfx.quit_game calla el audio antes de cerrar). Lo usa tests/smoke.sh.
##   godot --headless --path . -s tests/run_scene.gd -- res://ruta/Escena.tscn [fotogramas]

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("Falta la escena: -- res://ruta/Escena.tscn")
		quit(1)
		return
	var packed: PackedScene = load(args[0])
	if packed == null:
		push_error("No se puede cargar %s" % args[0])
		quit(1)
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	current_scene = scene
	var frames := int(args[1]) if args.size() > 1 else 300
	for i in frames:
		await process_frame
	load("res://scripts/util/Sfx.gd").quit_game(self)
