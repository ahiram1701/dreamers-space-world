class_name UIAnim
extends RefCounted
## Abrir y cerrar paneles con un fundido y un desplazamiento corto: nada aparece de golpe.

const TIME := 0.18


static func show(c: CanvasItem, offset: Vector2 = Vector2(0, 14)) -> void:
	c.visible = true
	c.modulate.a = 0.0
	var tw := c.create_tween().set_parallel().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(c, "modulate:a", 1.0, TIME)
	# Dentro de un contenedor la posición la decide él: solo fundido
	if c is Control and offset != Vector2.ZERO and not (c.get_parent() is Container):
		var ctrl := c as Control
		var to := ctrl.position
		ctrl.position = to + offset
		tw.tween_property(ctrl, "position", to, TIME)


static func hide(c: CanvasItem) -> void:
	if not c.visible:
		return
	var tw := c.create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(c, "modulate:a", 0.0, TIME * 0.8)
	tw.tween_callback(func(): c.visible = false; c.modulate.a = 1.0)
