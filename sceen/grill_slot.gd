## 铁板单格：Marker2D 吸附点与占用状态（slot_index 0~3 上排，4~7 下排）。
extends Node2D
class_name GrillSlot

@export var slot_index: int = 0

var patty: Patty = null

@onready var marker: Marker2D = $Marker2D


func is_empty() -> bool:
	return patty == null


func snap_global_position() -> Vector2:
	return marker.global_position


func assign_patty(new_patty: Patty) -> void:
	patty = new_patty


func clear_patty() -> void:
	patty = null
