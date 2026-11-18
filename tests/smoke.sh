#!/usr/bin/env bash
# Arranca las escenas principales sin ventana y falla si Godot imprime errores o si, al cerrar,
# algo se queda sin liberar.
# Godot no cambia el código de salida ante errores de GDScript, así que hay que leer la salida.
#   bash tests/smoke.sh        (requiere `godot` en el PATH, o GODOT=/ruta/al/binario)
set -uo pipefail

GODOT="${GODOT:-godot}"
if ! command -v "$GODOT" >/dev/null 2>&1; then
	echo "::error::No se encuentra Godot ($GODOT): las escenas no se han probado"
	exit 1
fi
SCENES=(
	"res://scenes/main_menu/MainMenu.tscn"
	"res://scenes/act0_town/Act0Town.tscn"
	"res://scenes/dev/AITestScene.tscn"
	"res://scenes/generated_location/GeneratedLocation.tscn"
	"res://scenes/space/SpaceScene.tscn"
)
# mesh_get_surface_count y material_get_instance_shader_parameters en servers/rendering/dummy
IGNORE='Parameter "(m|material)" is null'
status=0

for scene in "${SCENES[@]}"; do
	echo "::group::$scene"
	# Se cierra como lo hace el jugador (en orden, ver tests/run_scene.gd): así se ve también si
	# algo se queda sin liberar al salir («leaked at exit»)
	log="$("$GODOT" --headless --path . -s tests/run_scene.gd -- "$scene" 300 2>&1)"
	echo "$log"
	echo "::endgroup::"
	# Ruido conocido del renderizador "dummy" de --headless: no son errores del juego
	errors="$(grep -E 'SCRIPT ERROR|Parse Error|ERROR:|leaked at exit' <<<"$log" | grep -vE "$IGNORE" || true)"
	if [[ -n "$errors" ]]; then
		echo "$errors" | sort | uniq -c
		echo "::error::Errores al ejecutar $scene"
		status=1
	else
		echo "✔ $scene"
	fi
done

exit $status
