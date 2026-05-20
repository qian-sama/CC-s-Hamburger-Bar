## 铁板单格：Marker2D 吸附点与占用状态（slot_index 0~3 上排，4~7 下排）。
extends Node2D
class_name GrillSlot

## 槽位编号（0~7，上排 0~3、下排 4~7）
@export var slot_index: int = 0

## 当前槽内的肉饼；空槽为 null
var patty: Patty = null

@onready var marker: Marker2D = $Marker2D


## 槽位是否空闲
func is_empty() -> bool:
	return patty == null


## 肉饼应吸附的世界坐标
func snap_global_position() -> Vector2:
	return marker.global_position


## 将肉饼绑定到本槽
func assign_patty(new_patty: Patty) -> void:
	patty = new_patty


## 清空槽位引用（不销毁肉饼节点）
func clear_patty() -> void:
	patty = null
