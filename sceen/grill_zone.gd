## 【已弃用】请改用 interact_zone.gd，并在检查器里设置 target_scene。
extends Area2D

func _on_body_entered(body: Node2D) -> void:
	if body.has_method("show_interact_prompt"):
		body.show_interact_prompt()


func _on_body_exited(body: Node2D) -> void:
	if body.has_method("hide_interact_prompt"):
		body.hide_interact_prompt()
