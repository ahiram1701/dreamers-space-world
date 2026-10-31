extends SceneTree
## El guardado: muchos cambios seguidos se escriben una sola vez, nunca queda el archivo a medias
## (.tmp) y, si el archivo principal se daña, se recupera la copia anterior (.bak).
##   godot --headless --path . -s tests/test_save.gd

var _failed := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var db = root.get_node("/root/WorldDB")
	var previous_last: String = db.last_world_id()
	var id: String = db.create_world("Prueba de guardado")
	var path := "user://worlds/%s/world.json" % id
	_expect(FileAccess.file_exists(path), "crear un mundo lo escribe en el acto")

	var before: int = db.writes
	for i in 200:
		db.set_state("contador", i)
	_expect(db.writes == before, "200 cambios seguidos no escriben nada todavía")
	await create_timer(db.SAVE_DELAY + 0.5).timeout
	_expect(db.writes == before + 1, "y luego se escriben una sola vez (%d escrituras)" % (db.writes - before))
	_expect(not FileAccess.file_exists(path + ".tmp"), "no queda ningún .tmp")
	_expect(JSON.parse_string(FileAccess.get_file_as_string(path)).state.contador == 199, "lo escrito es lo último")

	db.set_state("contador", 500)
	db.flush()
	_expect(FileAccess.file_exists(path + ".bak"), "la versión anterior queda como .bak")
	# Se corrompe el archivo principal (p. ej. un corte de luz): se recupera la copia
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("{\"format_version\": 1, \"entit")
	f.close()
	_expect(db.load_world(id) and db.recovered_from_backup, "un archivo dañado se recupera de la copia")
	_expect(int(db.get_state("contador", -1)) == 199, "con lo que había en la copia (%s)" % db.get_state("contador", -1))

	db.delete_world(id)
	_expect(not FileAccess.file_exists(path) and not FileAccess.file_exists(path + ".bak"), "borrar el mundo borra también las copias")
	db.set_last_world_id(previous_last)
	print("\n%s" % ("TODO OK" if _failed == 0 else "%d FALLOS" % _failed))
	quit(_failed)


func _expect(cond: bool, msg: String) -> void:
	print(("  ✔ " if cond else "  ✘ ") + msg)
	if not cond:
		_failed += 1
