extends Node
class_name GameStateService

## 从主场景进入分区后，返回主场景时恢复玩家站立位置。
const MAIN_SCENE := "res://sceen/主场景.tscn"
const GRILL_SCENE := "res://sceen/grill_sceen.tscn"
const ASSEMBLE_SCENE := "res://sceen/assemble.tscn"
const CASHIER_SCENE := "res://sceen/收银区.tscn"

## 熟肉 FIFO 队列上限（先入先出，组装时从队首取）
const MAX_COOKED_PATTIES := 8
## 成品盘汉堡数量上限
const MAX_FINISHED_BURGERS := 6

## 顾客刷客间隔（秒）
const CUSTOMER_SPAWN_MIN_SEC := 20.0
const CUSTOMER_SPAWN_MAX_SEC := 60.0
const MAX_ACTIVE_CUSTOMERS := 12
const MAX_PICKUP_QUEUE := 6

enum CustomerPhase {
	PENDING,
	WALKING_IN,
	AT_COUNTER,
	WALKING_PICKUP,
	WAITING_PICKUP,
}

signal cooked_patties_changed
signal finished_burgers_changed
signal customer_spawned(customer_id: int)
signal customer_ordered(customer_id: int)
signal pickup_queue_changed()

var hub_return_position: Vector2 = Vector2.ZERO
var has_hub_return: bool = false

## 队首 = 下一块待组装；队尾 = 最近入库
var cooked_patty_doneness_list: Array[int] = []
var last_cooked_doneness: int = -1

## 每个元素为一层列表：[{ "type": int, "doneness": int }, ...]
var finished_burgers: Array = []

## 组装案板上未提交的汉堡（下包→馅料→顶包）；空数组表示无半成品
var assembly_plate_layers: Array = []

## 离开煎肉区时保存的铁板槽位快照（切换场景后恢复煎制进度）
var grill_patty_snapshots: Array[Dictionary] = []
## 离开煎肉区的时刻（毫秒），用于离线继续煎制
var _grill_left_at_msec: int = -1

var _customers: Dictionary = {}
var _walk_in_queue: Array[int] = []
var _pickup_queue: Array[int] = []
var _spawn_countdown: float = 0.0
var _next_customer_id: int = 1
var _counter_busy: bool = false
var _active_counter_customer_id: int = -1


func _ready() -> void:
	_spawn_countdown = randf_range(5.0, 12.0)
	set_process(true)


## 进入收银区时若尚无顾客，立即刷一位以便排队流程能跑起来。
func ensure_customer_presence() -> void:
	if not _customers.is_empty():
		return
	_try_spawn_customer()
	_reset_spawn_timer()


func _process(delta: float) -> void:
	_spawn_countdown -= delta
	if _spawn_countdown > 0.0:
		return
	_try_spawn_customer()
	_reset_spawn_timer()


func get_cooked_count() -> int:
	return cooked_patty_doneness_list.size()


## 与列表长度一致，供旧代码读取
var cooked_patty_count: int:
	get:
		return cooked_patty_doneness_list.size()


func can_add_cooked_patty() -> bool:
	return cooked_patty_doneness_list.size() < MAX_COOKED_PATTIES


## 入库：追加到队尾（FIFO）；doneness 为 Patty.Doneness 整型值 1~4
func add_cooked_patty(doneness: int) -> bool:
	if not can_add_cooked_patty():
		return false
	if doneness < Patty.Doneness.THREE_MIN:
		push_warning("GameState: 拒绝生肉入库 doneness=%s" % doneness)
		return false
	cooked_patty_doneness_list.append(doneness)
	last_cooked_doneness = doneness
	cooked_patties_changed.emit()
	return true


## 组装取肉：从队首取出（先入库的先组装），无肉时返回 -1
func take_next_cooked_patty() -> int:
	if cooked_patty_doneness_list.is_empty():
		return -1
	var doneness: int = cooked_patty_doneness_list.pop_front()
	cooked_patties_changed.emit()
	return doneness


## 查看队首熟度，不取出；-1 表示空队列
func peek_next_cooked_doneness() -> int:
	if cooked_patty_doneness_list.is_empty():
		return -1
	return cooked_patty_doneness_list[0]


func get_finished_count() -> int:
	return finished_burgers.size()


func can_add_finished_burger() -> bool:
	return finished_burgers.size() < MAX_FINISHED_BURGERS


## 成品盘入库：layers 为组装台导出的层字典数组。
func add_finished_burger(layers: Array) -> bool:
	if not can_add_finished_burger() or layers.is_empty():
		return false
	var burger_copy: Array = []
	for layer in layers:
		if layer is Dictionary:
			burger_copy.append(layer.duplicate())
	if burger_copy.is_empty():
		return false
	finished_burgers.append(burger_copy)
	finished_burgers_changed.emit()
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


func save_grill_patty_snapshots(snapshots: Array) -> void:
	grill_patty_snapshots.clear()
	for snap in snapshots:
		if snap is Dictionary:
			grill_patty_snapshots.append(snap.duplicate())
	mark_grill_left()


## 记录离开煎肉区时间，铁板肉饼在其它场景期间继续计时
func mark_grill_left() -> void:
	_grill_left_at_msec = Time.get_ticks_msec()


## 回到煎肉区时取走离线秒数并重置计时点；未离开过则返回 0
func consume_grill_absent_seconds() -> float:
	if _grill_left_at_msec < 0:
		return 0.0
	var elapsed := (Time.get_ticks_msec() - _grill_left_at_msec) / 1000.0
	_grill_left_at_msec = -1
	return maxf(elapsed, 0.0)


func save_hub_return(position: Vector2) -> void:
	hub_return_position = position
	has_hub_return = true


func clear_hub_return() -> void:
	has_hub_return = false


func save_assembly_plate(layers: Array) -> void:
	assembly_plate_layers.clear()
	for layer in layers:
		if layer is Dictionary:
			assembly_plate_layers.append(layer.duplicate())


func clear_assembly_plate() -> void:
	assembly_plate_layers.clear()


func get_assembly_plate_layers() -> Array:
	var copy: Array = []
	for layer in assembly_plate_layers:
		if layer is Dictionary:
			copy.append(layer.duplicate())
	return copy


func _reset_spawn_timer() -> void:
	_spawn_countdown = randf_range(CUSTOMER_SPAWN_MIN_SEC, CUSTOMER_SPAWN_MAX_SEC)


func _try_spawn_customer() -> void:
	if _customers.size() >= MAX_ACTIVE_CUSTOMERS:
		return
	if _pickup_queue.size() >= MAX_PICKUP_QUEUE and _walk_in_queue.size() >= 3:
		return
	var layers := OrderGenerator.generate_order_layers()
	var customer_id := _next_customer_id
	_next_customer_id += 1
	_customers[customer_id] = {
		"id": customer_id,
		"layers": layers,
		"phase": CustomerPhase.PENDING,
	}
	_walk_in_queue.append(customer_id)
	customer_spawned.emit(customer_id)


func get_all_customer_ids() -> Array:
	return _customers.keys()


func get_customer_phase(customer_id: int) -> int:
	var record = _customers.get(customer_id)
	if record == null:
		return -1
	return record.get("phase", -1)


func set_customer_phase(customer_id: int, phase: int) -> void:
	var record = _customers.get(customer_id)
	if record == null:
		return
	record["phase"] = phase


func get_customer_layers(customer_id: int) -> Array:
	var record = _customers.get(customer_id)
	if record == null:
		return []
	var copy: Array = []
	for layer in record.get("layers", []):
		if layer is Dictionary:
			copy.append(layer.duplicate())
	return copy


func get_pickup_queue() -> Array:
	return _pickup_queue.duplicate()


func pop_next_walk_in() -> int:
	while not _walk_in_queue.is_empty():
		var customer_id: int = _walk_in_queue.pop_front()
		if not _customers.has(customer_id):
			continue
		if get_customer_phase(customer_id) == CustomerPhase.PENDING:
			return customer_id
	return -1


func push_walk_in_front(customer_id: int) -> void:
	if customer_id in _walk_in_queue:
		_walk_in_queue.erase(customer_id)
	_walk_in_queue.insert(0, customer_id)


func is_counter_busy() -> bool:
	return _counter_busy


func get_active_counter_customer_id() -> int:
	return _active_counter_customer_id


func claim_counter(customer_id: int) -> bool:
	if _counter_busy:
		return false
	_counter_busy = true
	_active_counter_customer_id = customer_id
	return true


func release_counter() -> void:
	_counter_busy = false
	_active_counter_customer_id = -1


func release_counter_if(customer_id: int) -> void:
	if _active_counter_customer_id == customer_id:
		release_counter()


func enqueue_pickup(customer_id: int) -> int:
	if customer_id in _pickup_queue:
		return _pickup_queue.find(customer_id)
	_pickup_queue.append(customer_id)
	customer_ordered.emit(customer_id)
	pickup_queue_changed.emit()
	return _pickup_queue.size() - 1
