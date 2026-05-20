## 收银点单区：玩家进入后才可开始接待柜台顾客。
extends Area2D

signal player_entered(player: Node2D)
signal player_exited(player: Node2D)


func _ready() -> void:
	# 出生时已在区内时 body_entered 不会触发，需补检一次
	await get_tree().physics_frame
	for body in get_overlapping_bodies():
		_on_body_entered(body)


func _on_body_entered(body: Node2D) -> void:
	if _is_player(body):
		player_entered.emit(body)


func _on_body_exited(body: Node2D) -> void:
	if _is_player(body):
		player_exited.emit(body)


## 仅识别带 set_cashier_hint 的玩家角色。
func _is_player(body: Node2D) -> bool:
	return body is CharacterBody2D and body.has_method("set_cashier_hint")
