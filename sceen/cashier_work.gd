## 收银区：顾客走道 → 点单 → 取餐排队；仅在本场景显示顾客。
extends Node2D

const CUSTOMER_SCENE := preload("res://sceen/顾客.tscn")
const WALK_SPEED := 52.0
const PICKUP_SLOT_COUNT := 6  # 取餐位 Marker 数量上限

@onready var _customers_root: Node2D = $Customers
@onready var _walk_entrance: Marker2D = $Markers/WalkEntrance
@onready var _walk_mid: Marker2D = $Markers/WalkMid
@onready var _counter: Marker2D = $Markers/CounterPoint
@onready var _pickup_mid: Marker2D = $Markers/PickupWalkMid
@onready var _pickup_slots: Node2D = $Markers/PickupQueue
@onready var _order_panel: OrderPanel = $UI/OrderPanel
@onready var _order_zone: Area2D = $OrderZone
@onready var _pickup_deliver_zone: Area2D = $PickupDeliverZone
@onready var _leave_route: Node2D = $Markers/LeaveRoute
@onready var _pickup_finished_plate: FinishedBurgerPlate = $PickupFinishedPlate

var _actors: Dictionary = {}  # customer_id -> CustomerActor
var _order_timer: SceneTreeTimer = null  # 预留：定时点单（当前未使用）
var _player_in_order_zone: bool = false       # 玩家是否在点单区
var _player_in_pickup_deliver_zone: bool = false  # 玩家是否在取餐交付区
var _pending_order_customer_id: int = -1      # 已到柜台、待玩家进入点单区后展示订单


func _ready() -> void:
	_order_panel.hide_order()  # 中央 OrderPanel 已弃用，改在顾客身旁气泡显示
	var game_state := _get_game_state()
	if game_state == null:
		return
	if not game_state.customer_spawned.is_connected(_on_customer_spawned):
		game_state.customer_spawned.connect(_on_customer_spawned)
	if not game_state.pickup_queue_changed.is_connected(_on_pickup_queue_changed):
		game_state.pickup_queue_changed.connect(_on_pickup_queue_changed)
	if _order_zone.has_signal("player_entered"):
		_order_zone.player_entered.connect(_on_player_entered_order_zone)
		_order_zone.player_exited.connect(_on_player_exited_order_zone)
	if _pickup_deliver_zone.has_signal("player_entered"):
		_pickup_deliver_zone.player_entered.connect(_on_player_entered_pickup_zone)
		_pickup_deliver_zone.player_exited.connect(_on_player_exited_pickup_zone)
	await get_tree().physics_frame
	_sync_player_zones_overlap()
	_sync_scene_from_state()
	if game_state.is_session_active():
		if game_state.get_all_customer_ids().is_empty():
			game_state.ensure_customer_presence()
		_try_start_walk_in()


## 离开收银场景：清提示、断开信号、回收顾客节点并规范化 GameState。
func _exit_tree() -> void:
	_clear_player_order_hint()
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


## 新顾客刷出后尝试启动进店流程。
func _on_customer_spawned(_customer_id: int) -> void:
	_try_start_walk_in()


## 取餐队列变化时重排站位与朝向。
func _on_pickup_queue_changed() -> void:
	_relayout_pickup_queue()
	_refresh_queue_idle_facings()


## 在取餐区按 P 向队首顾客交付成品汉堡。
func _unhandled_input(event: InputEvent) -> void:
	var game_state := _get_game_state()
	if game_state != null and not game_state.is_session_active():
		return
	if not event.is_action_pressed("PlacePatty"):
		return
	if not _player_in_pickup_deliver_zone:
		return
	if not _try_deliver_front_customer():
		return
	var viewport := get_viewport()
	if viewport:
		viewport.set_input_as_handled()


## 从 walk_in 取一位顾客进店（占柜台 → 行走 → 柜台点单）。
func _try_start_walk_in() -> void:
	var game_state := _get_game_state()
	if game_state == null or not game_state.is_session_active() or game_state.is_counter_busy():
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


## 顾客到达柜台：等待玩家进入点单区后播放订单写出。
func _on_reached_counter(customer_id: int) -> void:
	var game_state := _get_game_state()
	if game_state == null:
		return
	game_state.set_customer_phase(customer_id, GameStateService.CustomerPhase.AT_COUNTER)
	var actor := _actors.get(customer_id) as CustomerActor
	if actor:
		actor.prepare_at_counter()
	_pending_order_customer_id = customer_id
	_update_cashier_hints()
	_try_begin_pending_order()


## 玩家进入点单区：更新提示并尝试开始订单写出。
func _on_player_entered_order_zone(_player: Node2D) -> void:
	_player_in_order_zone = true
	_update_cashier_hints()
	_try_begin_pending_order()


func _on_player_exited_order_zone(_player: Node2D) -> void:
	_player_in_order_zone = false
	_update_cashier_hints()


## 玩家进入取餐交付区。
func _on_player_entered_pickup_zone(_player: Node2D) -> void:
	_player_in_pickup_deliver_zone = true
	_update_cashier_hints()


func _on_player_exited_pickup_zone(_player: Node2D) -> void:
	_player_in_pickup_deliver_zone = false
	_update_cashier_hints()


## 玩家已在点单区且柜台有待点单顾客时，启动订单气泡写出。
func _try_begin_pending_order() -> void:
	if _pending_order_customer_id < 0 or not _player_in_order_zone:
		return
	var customer_id := _pending_order_customer_id
	_pending_order_customer_id = -1
	_start_order_reveal(customer_id)


## 连接 reveal 完成回调并让顾客身旁逐层显示订单。
func _start_order_reveal(customer_id: int) -> void:
	var game_state := _get_game_state()
	if game_state == null:
		return
	_update_cashier_hints()
	var layers: Array = game_state.get_customer_layers(customer_id)
	var actor := _actors.get(customer_id) as CustomerActor
	if actor == null:
		_finish_order_at_counter(customer_id)
		return
	_cancel_order_timer()
	if actor.order_reveal_finished.is_connected(_on_counter_order_done):
		actor.order_reveal_finished.disconnect(_on_counter_order_done)
	actor.order_reveal_finished.connect(
		_on_counter_order_done.bind(customer_id),
		CONNECT_ONE_SHOT
	)
	actor.begin_order_reveal(layers)


## 订单写出动画结束。
func _on_counter_order_done(customer_id: int) -> void:
	_finish_order_at_counter(customer_id)


## 点单完成：入取餐队、释放柜台、顾客走向取餐位。
func _finish_order_at_counter(customer_id: int) -> void:
	if _pending_order_customer_id == customer_id:
		_pending_order_customer_id = -1
	_update_cashier_hints()
	var actor := _actors.get(customer_id) as CustomerActor
	if actor:
		actor.hide_order_bubble()
	var game_state := _get_game_state()
	if game_state == null:
		return
	var pickup_index := game_state.enqueue_pickup(customer_id)
	game_state.set_customer_phase(customer_id, GameStateService.CustomerPhase.WALKING_PICKUP)
	game_state.release_counter()
	_try_start_walk_in()
	if actor == null:
		return
	actor.walk_through_world(_walk_pickup_points(pickup_index), WALK_SPEED)
	actor.walk_finished.connect(
		func() -> void: _on_reached_pickup(customer_id, pickup_index),
		CONNECT_ONE_SHOT
	)


## 顾客到达取餐位：进入 WAITING_PICKUP 并播放队列待机朝向。
func _on_reached_pickup(customer_id: int, pickup_index: int) -> void:
	var game_state := _get_game_state()
	if game_state:
		game_state.set_customer_phase(customer_id, GameStateService.CustomerPhase.WAITING_PICKUP)
	var actor := _actors.get(customer_id) as CustomerActor
	if actor:
		actor.set_queue_idle(pickup_index)


## 向取餐队首交付成品汉堡（消耗 finished_burgers 队首）并让顾客沿离开路线走出。
func _try_deliver_front_customer() -> bool:
	var game_state := _get_game_state()
	if game_state == null:
		return false
	var pickup_index := 0
	if not game_state.get_pickup_queue().is_empty():
		var front_id: int = game_state.get_front_pickup_customer_id()
		var queue := game_state.get_pickup_queue()
		if front_id in queue:
			pickup_index = queue.find(front_id)
	var customer_id := game_state.deliver_to_front_pickup_customer()
	if customer_id < 0:
		_update_cashier_hints()
		return false
	var actor := _actors.get(customer_id) as CustomerActor
	if actor == null:
		return true
	game_state.set_customer_phase(customer_id, GameStateService.CustomerPhase.LEAVING)
	actor.hide_order_bubble()
	actor.walk_through_world(_walk_leave_points(pickup_index), WALK_SPEED)
	actor.walk_finished.connect(
		func() -> void: _on_customer_left_pickup(customer_id),
		CONNECT_ONE_SHOT
	)
	_update_cashier_hints()
	return true


## 顾客离开动画结束：销毁节点并从 _actors 移除。
func _on_customer_left_pickup(customer_id: int) -> void:
	var actor := _actors.get(customer_id) as CustomerActor
	if actor and is_instance_valid(actor):
		actor.stop_walking()
		actor.queue_free()
	_actors.erase(customer_id)


## 进入收银区时根据 GameState 重建取餐队与柜台顾客。
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
			var actor := _spawn_actor(active_id, _counter.global_position)
			actor.prepare_at_counter()
			_pending_order_customer_id = active_id
			_try_begin_pending_order()
		elif active_phase == GameStateService.CustomerPhase.WALKING_IN:
			game_state.set_customer_phase(active_id, GameStateService.CustomerPhase.PENDING)
			game_state.release_counter()
			game_state.push_walk_in_front(active_id)


## 离开收银区时把「行走中」顾客还原为可重试的 PENDING / WAITING 状态。
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


## 实例化顾客并登记到 _actors。
func _spawn_actor(customer_id: int, world_pos: Vector2) -> CustomerActor:
	var actor := CUSTOMER_SCENE.instantiate() as CustomerActor
	actor.setup(customer_id)
	_customers_root.add_child(actor)
	actor.snap_to_world(world_pos)
	_actors[customer_id] = actor
	return actor


## 销毁场景中所有顾客 Actor。
func _despawn_all_actors() -> void:
	for customer_id in _actors.keys():
		var actor = _actors[customer_id]
		if is_instance_valid(actor):
			(actor as CustomerActor).stop_walking()
			actor.queue_free()
	_actors.clear()


## 进店路径：入口 → 中段 → 柜台。
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


## 队首离开路线（右拐）：起点=当前取餐位 → LeaveRoute 子节点按名称排序。
## 可在 Markers/LeaveRoute 下拖动 1_Right、2_RightMid、3_Exit 等 Marker2D 微调。
func _walk_leave_points(from_slot_index: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	points.append(_pickup_slot_position(from_slot_index))
	var leave_markers := _collect_leave_route_markers()
	if not leave_markers.is_empty():
		for marker in leave_markers:
			points.append(marker.global_position)
		return points
	# 无 LeaveRoute 时退回旧路线
	points.append(_pickup_mid.global_position)
	points.append(_walk_mid.global_position)
	points.append(_walk_entrance.global_position)
	return points


## 收集 LeaveRoute 下 Marker2D 并按名称自然排序。
func _collect_leave_route_markers() -> Array[Marker2D]:
	var markers: Array[Marker2D] = []
	if _leave_route == null:
		return markers
	for child in _leave_route.get_children():
		if child is Marker2D:
			markers.append(child)
	markers.sort_custom(func(a: Marker2D, b: Marker2D) -> bool:
		return a.name.naturalnocasecmp_to(b.name) < 0
	)
	return markers


## 取餐队列变化时把 WAITING 顾客 snap 到对应槽位坐标。
func _relayout_pickup_queue() -> void:
	var game_state := _get_game_state()
	if game_state == null:
		return
	for i in game_state.get_pickup_queue().size():
		var customer_id: int = game_state.get_pickup_queue()[i]
		var actor := _actors.get(customer_id) as CustomerActor
		if actor == null:
			continue
		if game_state.get_customer_phase(customer_id) \
				== GameStateService.CustomerPhase.WAITING_PICKUP:
			actor.snap_to_world(_pickup_slot_position(i))


## 刷新取餐队列中每位顾客的待机朝向（前 3 背 / 后 3 正）。
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


## 取餐位 index 对应的世界坐标。
func _pickup_slot_position(index: int) -> Vector2:
	var markers := _collect_pickup_markers()
	if markers.is_empty():
		return _pickup_mid.global_position
	var slot_index := clampi(index, 0, mini(markers.size(), PICKUP_SLOT_COUNT) - 1)
	return markers[slot_index].global_position


## 收集 PickupQueue 下 Marker2D 并按名称排序。
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


## 场景加载后根据 Area 重叠体恢复玩家是否在点单/取餐区。
func _sync_player_zones_overlap() -> void:
	_player_in_order_zone = not _get_overlapping_players(_order_zone).is_empty()
	_player_in_pickup_deliver_zone = not _get_overlapping_players(_pickup_deliver_zone).is_empty()
	_update_cashier_hints()


## 获取指定 Area 内所有玩家 CharacterBody2D。
func _get_overlapping_players(zone: Area2D) -> Array[Node2D]:
	var result: Array[Node2D] = []
	if zone == null:
		return result
	for body in zone.get_overlapping_bodies():
		if body is CharacterBody2D and body.has_method("set_cashier_hint"):
			result.append(body)
	return result


## 根据点单/取餐区状态更新玩家头顶收银提示文案。
func _update_cashier_hints() -> void:
	var player := _get_player()
	if player == null:
		return
	if _pending_order_customer_id >= 0 and not _player_in_order_zone:
		player.set_cashier_hint("请到点单区接待顾客")
		return
	if _player_in_pickup_deliver_zone:
		var game_state := _get_game_state()
		if game_state and game_state.can_deliver_pickup():
			player.set_cashier_hint("按 P 交付汉堡")
		elif game_state and game_state.get_finished_count() <= 0:
			player.set_cashier_hint("成品盘无汉堡")
		elif game_state and game_state.get_pickup_queue().is_empty():
			player.set_cashier_hint("暂无取餐顾客")
		else:
			player.set_cashier_hint("按 P 交付")
		return
	player.clear_cashier_hint()


## 离开场景时清除玩家收银提示。
func _clear_player_order_hint() -> void:
	var player := _get_player()
	if player:
		player.clear_cashier_hint()


## 获取本场景 Players 节点。
func _get_player() -> CharacterBody2D:
	var node := get_node_or_null("Players")
	return node as CharacterBody2D


## 获取 autoload GameState 单例。
func _get_game_state() -> GameStateService:
	return get_tree().root.get_node_or_null("GameState") as GameStateService
