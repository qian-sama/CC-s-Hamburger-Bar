## 熟肉区展示：与 GameState FIFO 队列同步，Slot0 = 队首（下一块组装）。
extends Area2D
class_name CookedPattyHolder

const MAX_PATTIES := 8
const PATTY_SCENE: PackedScene = preload("res://sceen/肉饼.tscn")

@onready var _display_root: Node2D = $DisplayedPatties
@onready var _slot_markers: Node2D = $DisplaySlots

var _markers: Array[Marker2D] = []
var _stored: Array[Patty] = []


func _ready() -> void:
	_collect_markers()
	var game_state := _get_game_state()
	if game_state and not game_state.cooked_patties_changed.is_connected(_on_cooked_patties_changed):
		game_state.cooked_patties_changed.connect(_on_cooked_patties_changed)
	sync_from_game_state()


func _on_cooked_patties_changed() -> void:
	sync_from_game_state()


func _get_game_state() -> GameStateService:
	return get_tree().root.get_node_or_null("GameState") as GameStateService


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
	var game_state := _get_game_state()
	if game_state:
		return not game_state.can_add_cooked_patty()
	return _stored.size() >= MAX_PATTIES


func has_space() -> bool:
	return not is_full()


## 按 GameState 队列顺序重建画面（索引 0 对应队首 / Slot0）
func sync_from_game_state() -> void:
	_clear_display()
	var game_state := _get_game_state()
	if game_state == null:
		return
	var queue: Array[int] = game_state.cooked_patty_doneness_list
	for i in queue.size():
		var doneness: int = queue[i]
		var patty := _spawn_frozen_patty(doneness)
		_place_patty_at_slot(patty, i)
		_stored.append(patty)


func _clear_display() -> void:
	for patty in _stored:
		if is_instance_valid(patty):
			patty.queue_free()
	_stored.clear()
	for child in _display_root.get_children():
		child.queue_free()


func _spawn_frozen_patty(doneness: int) -> Patty:
	var patty := PATTY_SCENE.instantiate() as Patty
	_display_root.add_child(patty)
	patty.setup_cooked_display(doneness as Patty.Doneness)
	return patty


func _place_patty_at_slot(patty: Patty, index: int) -> void:
	var marker := _markers[index] if index < _markers.size() else null
	if marker != null:
		patty.global_position = marker.global_position
	patty.z_index = index
