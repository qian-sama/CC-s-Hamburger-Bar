## 收银区：顾客走道 → 点单 → 取餐排队；仅在本场景显示顾客。
extends Node2D

const CUSTOMER_SCENE := preload("res://sceen/顾客.tscn")
const ORDER_DISPLAY_SEC := 2.8
const WALK_SPEED := 52.0
const PICKUP_SLOT_COUNT := 6

@onready var _customers_root: Node2D = $Customers
@onready var _walk_entrance: Marker2D = $Markers/WalkEntrance
@onready var _walk_mid: Marker2D = $Markers/WalkMid
@onready var _counter: Marker2D = $Markers/CounterPoint
@onready var _pickup_mid: Marker2D = $Markers/PickupWalkMid
@onready var _pickup_slots: Node2D = $Markers/PickupQueue
@onready var _order_panel: OrderPanel = $UI/OrderPanel

var _actors: Dictionary = {}  # customer_id -> CustomerActor
var _order_timer: SceneTreeTimer = null


func _ready() -> void:
	_order_panel.hide_order()
	var game_state := _get_game_state()
	if game_state == null:
		return
	if not game_state.customer_spawned.is_connected(_on_customer_spawned):
		game_state.customer_spawned.connect(_on_customer_spawned)
	if not game_state.pickup_queue_changed.is_connected(_on_pickup_queue_changed):
		game_state.pickup_queue_changed.connect(_on_pickup_queue_changed)
	_sync_scene_from_state()
	if game_state.get_all_customer_ids().is_empty():
		game_state.ensure_customer_presence()
	_try_start_walk_in()


func _exit_tree() -> void:
	_cancel_order_timer()
	_normalize_state_on_leave()
	_despawn_all_actors()
	var game_state := _get_game_state()
	if game_state == null:
		return
	if game_state.customer_spawned.is_connected(_on_customer_spawned):
		game_state.customer_spawned.disconnect(_on_customer_spawned)
	if game_state.pickup_queue_changed.is_connected(_on_pickup_queue_changed):
		game_state.pickup_queue_changed.disconnect(_on_pickup_queue_changed)


func _on_customer_spawned(_customer_id: int) -> void:
	_try_start_walk_in()


func _on_pickup_queue_changed() -> void:
	_refresh_queue_idle_facings()


func _try_start_walk_in() -> void:
	var game_state := _get_game_state()
	if game_state == null or game_state.is_counter_busy():
		return
	var customer_id := game_state.pop_next_walk_in()
	if customer_id < 0:
		return
	if not game_state.claim_counter(customer_id):
		game_state.push_walk_in_front(customer_id)
		return
	game_state.set_customer_phase(customer_id, GameStateService.CustomerPhase.WALKING_IN)
	var actor := _spawn_actor(customer_id, _walk_entrance.global_position)
	actor.walk_through_world(_walk_in_points(), WALK_SPEED)
	actor.walk_finished.connect(
		func() -> void: _on_reached_counter(customer_id),
		CONNECT_ONE_SHOT
	)


func _on_reached_counter(customer_id: int) -> void:
	var game_state := _get_game_state()
	if game_state == null:
		return
	game_state.set_customer_phase(customer_id, GameStateService.CustomerPhase.AT_COUNTER)
	var layers: Array = game_state.get_customer_layers(customer_id)
	_order_panel.show_order(layers)
	_cancel_order_timer()
	_order_timer = get_tree().create_timer(ORDER_DISPLAY_SEC)
	_order_timer.timeout.connect(
		func() -> void: _finish_order_at_counter(customer_id),
		CONNECT_ONE_SHOT
	)


func _finish_order_at_counter(customer_id: int) -> void:
	_order_panel.hide_order()
	var game_state := _get_game_state()
	if game_state == null:
		return
	var pickup_index := game_state.enqueue_pickup(customer_id)
	game_state.set_customer_phase(customer_id, GameStateService.CustomerPhase.WALKING_PICKUP)
	game_state.release_counter()
	_try_start_walk_in()
	var actor := _actors.get(customer_id) as CustomerActor
	if actor == null:
		return
	actor.walk_through_world(_walk_pickup_points(pickup_index), WALK_SPEED)
	actor.walk_finished.connect(
		func() -> void: _on_reached_pickup(customer_id, pickup_index),
		CONNECT_ONE_SHOT
	)


func _on_reached_pickup(customer_id: int, pickup_index: int) -> void:
	var game_state := _get_game_state()
	if game_state:
		game_state.set_customer_phase(customer_id, GameStateService.CustomerPhase.WAITING_PICKUP)
	var actor := _actors.get(customer_id) as CustomerActor
	if actor:
		actor.set_queue_idle(pickup_index)


func _sync_scene_from_state() -> void:
	var game_state := _get_game_state()
	if game_state == null:
		return
	_despawn_all_actors()
	for i in game_state.get_pickup_queue().size():
		var customer_id: int = game_state.get_pickup_queue()[i]
		var phase: int = game_state.get_customer_phase(customer_id)
		if phase == GameStateService.CustomerPhase.WALKING_PICKUP:
			game_state.set_customer_phase(customer_id, GameStateService.CustomerPhase.WAITING_PICKUP)
			phase = GameStateService.CustomerPhase.WAITING_PICKUP
		if phase == GameStateService.CustomerPhase.WAITING_PICKUP:
			var actor := _spawn_actor(customer_id, _pickup_slot_position(i))
			actor.set_queue_idle(i)
	var active_id := game_state.get_active_counter_customer_id()
	if active_id >= 0:
		var active_phase := game_state.get_customer_phase(active_id)
		if active_phase == GameStateService.CustomerPhase.AT_COUNTER:
			_spawn_actor(active_id, _counter.global_position)
			_order_panel.show_order(game_state.get_customer_layers(active_id))
			_cancel_order_timer()
			_order_timer = get_tree().create_timer(ORDER_DISPLAY_SEC)
			_order_timer.timeout.connect(
				func() -> void: _finish_order_at_counter(active_id),
				CONNECT_ONE_SHOT
			)
		elif active_phase == GameStateService.CustomerPhase.WALKING_IN:
			game_state.set_customer_phase(active_id, GameStateService.CustomerPhase.PENDING)
			game_state.release_counter()
			game_state.push_walk_in_front(active_id)


func _normalize_state_on_leave() -> void:
	var game_state := _get_game_state()
	if game_state == null:
		return
	for customer_id in game_state.get_all_customer_ids():
		var phase := game_state.get_customer_phase(customer_id)
		match phase:
			GameStateService.CustomerPhase.WALKING_IN:
				game_state.set_customer_phase(customer_id, GameStateService.CustomerPhase.PENDING)
				game_state.push_walk_in_front(customer_id)
				game_state.release_counter_if(customer_id)
			GameStateService.CustomerPhase.WALKING_PICKUP:
				game_state.set_customer_phase(customer_id, GameStateService.CustomerPhase.WAITING_PICKUP)
	if game_state.is_counter_busy() and game_state.get_active_counter_customer_id() < 0:
		game_state.release_counter()


func _spawn_actor(customer_id: int, world_pos: Vector2) -> CustomerActor:
	var actor := CUSTOMER_SCENE.instantiate() as CustomerActor
	actor.setup(customer_id)
	_customers_root.add_child(actor)
	actor.snap_to_world(world_pos)
	_actors[customer_id] = actor
	return actor


func _despawn_all_actors() -> void:
	for customer_id in _actors.keys():
		var actor = _actors[customer_id]
		if is_instance_valid(actor):
			(actor as CustomerActor).stop_walking()
			actor.queue_free()
	_actors.clear()


func _walk_in_points() -> PackedVector2Array:
	return PackedVector2Array([
		_walk_entrance.global_position,
		_walk_mid.global_position,
		_counter.global_position,
	])


## 走向 n 号位（pickup_index：0=1号 … 5=6号）时，依次经过更靠后的槽位。
## 例如 1 号：6→5→4→3→2→1；6 号：直达 6。
func _walk_pickup_points(pickup_index: int) -> PackedVector2Array:
	var markers := _collect_pickup_markers()
	var points := PackedVector2Array()
	points.append(_counter.global_position)
	points.append(_pickup_mid.global_position)
	if markers.is_empty():
		return points
	var target_index := clampi(pickup_index, 0, markers.size() - 1)
	for slot_i in range(markers.size() - 1, target_index, -1):
		points.append(markers[slot_i].global_position)
	points.append(markers[target_index].global_position)
	return points


func _refresh_queue_idle_facings() -> void:
	var game_state := _get_game_state()
	if game_state == null:
		return
	for i in game_state.get_pickup_queue().size():
		var customer_id: int = game_state.get_pickup_queue()[i]
		var actor := _actors.get(customer_id) as CustomerActor
		if actor and game_state.get_customer_phase(customer_id) \
				== GameStateService.CustomerPhase.WAITING_PICKUP:
			actor.set_queue_idle(i)


func _pickup_slot_position(index: int) -> Vector2:
	var markers := _collect_pickup_markers()
	if markers.is_empty():
		return _pickup_mid.global_position
	var slot_index := clampi(index, 0, mini(markers.size(), PICKUP_SLOT_COUNT) - 1)
	return markers[slot_index].global_position


func _collect_pickup_markers() -> Array[Marker2D]:
	var markers: Array[Marker2D] = []
	for child in _pickup_slots.get_children():
		if child is Marker2D:
			markers.append(child)
	markers.sort_custom(func(a: Marker2D, b: Marker2D) -> bool:
		return a.name.naturalnocasecmp_to(b.name) < 0
	)
	return markers


func _cancel_order_timer() -> void:
	_order_timer = null


func _get_game_state() -> GameStateService:
	return get_tree().root.get_node_or_null("GameState") as GameStateService
