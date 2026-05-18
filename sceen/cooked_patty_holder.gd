## 熟肉区：最多展示 8 块肉饼，按入库时的熟度保留外观。
extends Area2D
class_name CookedPattyHolder

const MAX_PATTIES := 8

@onready var _display_root: Node2D = $DisplayedPatties
@onready var _slot_markers: Node2D = $DisplaySlots

var _markers: Array[Marker2D] = []
var _stored: Array[Patty] = []


func _ready() -> void:
	_collect_markers()


func _collect_markers() -> void:
	_markers.clear()
	for child in _slot_markers.get_children():
		if child is Marker2D:
			_markers.append(child)
	_markers.sort_custom(func(a: Marker2D, b: Marker2D) -> bool:
		return a.name.naturalnocasecmp_to(b.name) < 0
	)


func patty_count() -> int:
	return _stored.size()


func is_full() -> bool:
	return _stored.size() >= MAX_PATTIES


func has_space() -> bool:
	return not is_full()


## 将肉饼移入熟肉区展示位；成功返回 true。
func deposit(patty: Patty) -> bool:
	if is_full():
		return false
	var index := _stored.size()
	var marker := _markers[index] if index < _markers.size() else null
	patty.freeze_for_holder()
	_display_root.add_child(patty)
	if marker != null:
		patty.global_position = marker.global_position
	patty.z_index = index
	_stored.append(patty)
	return true
