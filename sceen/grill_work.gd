## 煎肉区玩法：站在冷藏区按 P 上架，站在铁板前按 I/O 取肉入熟肉区。
extends Node2D

const PATTY_SCENE: PackedScene = preload("res://sceen/肉饼.tscn")

@export var patty_time_scale: float = 1.0

@onready var _patties_root: Node2D = $Patties
@onready var _grill_plate: GrillPlate = $GrillPlate
@onready var _cold_storage: Area2D = $ColdStorage
@onready var _grill_pickup: Area2D = $GrillPickupZone
@onready var _cooked_holder: CookedPattyHolder = $CookedHolder

var _player_in_cold: bool = false
var _player_in_grill_pickup: bool = false
var _player: CharacterBody2D = null


func _ready() -> void:
	_cold_storage.body_entered.connect(_on_cold_body_entered)
	_cold_storage.body_exited.connect(_on_cold_body_exited)
	_grill_pickup.body_entered.connect(_on_grill_pickup_body_entered)
	_grill_pickup.body_exited.connect(_on_grill_pickup_body_exited)
	await get_tree().physics_frame
	_sync_overlapping_player(_cold_storage)
	_sync_overlapping_player(_grill_pickup)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
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
	if not patty.can_take_from_grill():
		_grill_plate.restore_patty_to_slot(patty, slot_index)
		return false
	if not _deposit_to_cooked_holder(patty):
		_grill_plate.restore_patty_to_slot(patty, slot_index)
		return false
	return true


func _deposit_to_cooked_holder(patty: Patty) -> bool:
	if not _cooked_holder.deposit(patty):
		return false
	var game_state := get_tree().root.get_node_or_null("GameState") as GameStateService
	if game_state:
		game_state.add_cooked_patty(patty.doneness)
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


func _update_grill_pickup_hint(body: Node2D) -> void:
	if _cooked_holder.is_full():
		_set_player_grill_hint(body, "熟肉区已满")
	else:
		_set_player_grill_hint(body, "I/O ")


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


func _sync_overlapping_player(area: Area2D) -> void:
	for body in area.get_overlapping_bodies():
		if area == _cold_storage:
			_on_cold_body_entered(body)
		elif area == _grill_pickup:
			_on_grill_pickup_body_entered(body)


func _is_player(body: Node2D) -> bool:
	return body is CharacterBody2D and body.has_method("set_grill_hint")
