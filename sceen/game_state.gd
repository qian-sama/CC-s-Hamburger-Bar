extends Node
class_name GameStateService

## 从主场景进入分区后，返回主场景时恢复玩家站立位置。
const MAIN_SCENE := "res://sceen/主场景.tscn"
const GRILL_SCENE := "res://sceen/grill_sceen.tscn"
const ASSEMBLE_SCENE := "res://sceen/assemble.tscn"

var hub_return_position: Vector2 = Vector2.ZERO
var has_hub_return: bool = false

## 已放入熟肉区的肉饼数量（组装区可读）
const MAX_COOKED_PATTIES := 8

## 煎肉区：已送入熟肉区的肉饼总数（与列表长度一致）
var cooked_patty_count: int = 0
## 每块熟肉的熟度（Patty.Doneness），供组装区读取
var cooked_patty_doneness_list: Array[int] = []
var last_cooked_doneness: int = -1


func add_cooked_patty(doneness: int) -> bool:
	if cooked_patty_doneness_list.size() >= MAX_COOKED_PATTIES:
		return false
	cooked_patty_doneness_list.append(doneness)
	cooked_patty_count = cooked_patty_doneness_list.size()
	last_cooked_doneness = doneness
	return true


func get_last_doneness_label() -> String:
	return get_doneness_label(last_cooked_doneness)


func get_doneness_label(doneness: int) -> String:
	match doneness:
		Patty.Doneness.THREE_MIN:
			return "三分熟"
		Patty.Doneness.SEVEN_MIN:
			return "七分熟"
		Patty.Doneness.WELL_DONE:
			return "全熟"
		Patty.Doneness.BURNT:
			return "焦"
		_:
			return ""


func save_hub_return(position: Vector2) -> void:
	hub_return_position = position
	has_hub_return = true


func clear_hub_return() -> void:
	has_hub_return = false
