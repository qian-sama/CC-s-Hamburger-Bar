## 煎肉区玩法：站在冷藏区按 P 上架，站在铁板前按 I/O 取肉入熟肉区。
extends Node2D

const PATTY_SCENE: PackedScene = preload("res://sceen/肉饼.tscn")

## 肉饼煎制速度倍率，传给每个新实例化的 Patty。
@export var patty_time_scale: float = 1.0

@onready var _patties_root: Node2D = $Patties
@onready var _grill_plate: GrillPlate = $GrillPlate
@onready var _cold_storage: Area2D = $ColdStorage
@onready var _grill_pickup: Area2D = $GrillPickupZone
@onready var _cooked_holder: CookedPattyHolder = $CookedHolder

## 玩家是否站在冷藏区 / 铁板取肉区（决定能否响应 P / I / O）。
var _player_in_cold: bool = false
var _player_in_grill_pickup: bool = false
## 当前在取肉区的玩家引用，用于按 X 坐标判断取哪一列。
var _player: CharacterBody2D = null


func _ready() -> void:
	_cold_storage.body_entered.connect(_on_cold_body_entered)
	_cold_storage.body_exited.connect(_on_cold_body_exited)
	_grill_pickup.body_entered.connect(_on_grill_pickup_body_entered)
	_grill_pickup.body_exited.connect(_on_grill_pickup_body_exited)
	# 若玩家出生时已在区域内，body_entered 不会触发，需主动检测一次重叠物体
	await get_tree().physics_frame
	_restore_grill_from_game_state()
	_sync_overlapping_player(_cold_storage)
	_sync_overlapping_player(_grill_pickup)
	_cooked_holder.sync_from_game_state()


## 离开煎肉区前由 interact_zone 调用，写入 GameState。
func save_grill_state_to_game() -> void:
	var game_state := _get_game_state()
	if game_state == null or not is_instance_valid(_grill_plate):
		return
	game_state.save_grill_patty_snapshots(_grill_plate.capture_grill_snapshots())


func _restore_grill_from_game_state() -> void:
	var game_state := _get_game_state()
	if game_state == null:
		return
	var absent_seconds := game_state.consume_grill_absent_seconds()
	if game_state.grill_patty_snapshots.is_empty():
		return
	_grill_plate.restore_grill_snapshots(
		game_state.grill_patty_snapshots, _patties_root, absent_seconds
	)


func _get_game_state() -> GameStateService:
	return get_tree().root.get_node_or_null("GameState") as GameStateService


## 全局输入：仅在对应区域内且操作成功时吞掉事件，避免影响其它 UI。
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	var game_state := _get_game_state()
	if game_state != null and not game_state.is_session_active():
		return
	if event.is_action_pressed("PlacePatty"):
		if _try_place_from_cold():
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("TakePattyTop"):
		if _try_harvest_row(0):
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("TakePattyBottom"):
		if _try_harvest_row(1):
			get_viewport().set_input_as_handled()


## 冷藏区按 P：在铁板第一个空位放一块生肉饼。
func _try_place_from_cold() -> bool:
	if not _player_in_cold:
		return false
	if _grill_plate.is_full():
		return false
	var slot_index := _grill_plate.find_first_empty_slot()
	if slot_index < 0:
		return false
	var patty := PATTY_SCENE.instantiate() as Patty
	patty.time_scale = patty_time_scale
	_patties_root.add_child(patty)
	return _grill_plate.place_patty(patty, slot_index)


## 铁板取肉区按 I（row=0）或 O（row=1）：按玩家 X 取对应列、指定行，成熟且熟肉区有格才成功。
func _try_harvest_row(row: int) -> bool:
	if not _player_in_grill_pickup or _player == null:
		return false
	if _cooked_holder.is_full():
		return false
	var column := _grill_plate.get_column_from_global_x(_player.global_position.x)
	var slot_index := GrillPlate.column_row_to_slot(column, row)
	var patty := _grill_plate.take_from_column(column, row)
	if patty == null:
		return false
	# 未煎好或熟肉区放不下时，把肉饼放回铁板原位
	if not patty.can_take_from_grill():
		_grill_plate.restore_patty_to_slot(patty, slot_index)
		return false
	if not _deposit_to_cooked_holder(patty):
		_grill_plate.restore_patty_to_slot(patty, slot_index)
		return false
	return true


## 入库：先写入 GameState 队尾，再按队列重建熟肉区画面（FIFO）。
func _deposit_to_cooked_holder(patty: Patty) -> bool:
	var game_state := _get_game_state()
	if game_state == null or not game_state.add_cooked_patty(int(patty.doneness)):
		return false
	patty.queue_free()
	_cooked_holder.sync_from_game_state()
	return true


func _on_cold_body_entered(body: Node2D) -> void:
	if not _is_player(body):
		return
	_player_in_cold = true
	_player = body as CharacterBody2D
	_set_player_grill_hint(body, "Press P")


func _on_cold_body_exited(body: Node2D) -> void:
	if not _is_player(body):
		return
	_player_in_cold = false
	_refresh_player_hint(body)


func _on_grill_pickup_body_entered(body: Node2D) -> void:
	if not _is_player(body):
		return
	_player_in_grill_pickup = true
	_player = body as CharacterBody2D
	_update_grill_pickup_hint(body)


func _on_grill_pickup_body_exited(body: Node2D) -> void:
	if not _is_player(body):
		return
	_player_in_grill_pickup = false
	_refresh_player_hint(body)


## 取肉区提示：熟肉区满时只显示错误文案，否则提示 I/O 两行操作。
func _update_grill_pickup_hint(body: Node2D) -> void:
	if _cooked_holder.is_full():
		_set_player_grill_hint(body, "熟肉区已满")
	else:
		_set_player_grill_hint(body, "I/O ")


## 离开一个区域后，若仍在另一区域则更新对应提示，否则清除。
func _refresh_player_hint(body: Node2D) -> void:
	if _player_in_grill_pickup:
		_update_grill_pickup_hint(body)
	elif _player_in_cold:
		_set_player_grill_hint(body, "Press P")
	else:
		_clear_player_grill_hint(body)


func _set_player_grill_hint(body: Node2D, text: String) -> void:
	if body.has_method("set_grill_hint"):
		body.set_grill_hint(text)


func _clear_player_grill_hint(body: Node2D) -> void:
	if body.has_method("clear_grill_hint"):
		body.clear_grill_hint()


## 场景加载后补发 enter 逻辑，与 interact_zone 的 _ready 重叠检测同理。
func _sync_overlapping_player(area: Area2D) -> void:
	for body in area.get_overlapping_bodies():
		if area == _cold_storage:
			_on_cold_body_entered(body)
		elif area == _grill_pickup:
			_on_grill_pickup_body_entered(body)


## 只响应带 set_grill_hint 的玩家角色，忽略其它 Body2D。
func _is_player(body: Node2D) -> bool:
	return body is CharacterBody2D and body.has_method("set_grill_hint")
