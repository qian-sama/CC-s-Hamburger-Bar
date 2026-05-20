## 全局游戏状态（autoload）：熟肉/成品 FIFO、案板、铁板快照、顾客与订单队列。
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

## 顾客在收银区的流程阶段
enum CustomerPhase {
	PENDING,          ## 已生成，等待进店
	WALKING_IN,       ## 走向柜台
	AT_COUNTER,       ## 在柜台（待点单展示）
	WALKING_PICKUP,   ## 走向取餐位
	WAITING_PICKUP,   ## 在取餐队列等候
	LEAVING,          ## 取餐完毕离开中
}

signal cooked_patties_changed    # 熟肉 FIFO 变化
signal finished_burgers_changed  # 成品盘队列变化
signal customer_spawned(customer_id: int)   # 新顾客入 walk_in 队列
signal customer_ordered(customer_id: int)   # 点单完成并入取餐队
signal pickup_queue_changed()    # 取餐队列顺序/人数变化
signal order_tickets_changed()   # 待做订单小票变化
signal money_changed(total: float, delta: float, perfect_match: bool)  # 交餐结算后收入变化
signal session_changed(phase: int)  # 开局 / 进行中 / 结算 阶段切换

## 一局游戏的流程阶段
enum SessionPhase {
	WAITING_START,  ## 启动后等待按 E 开始
	PLAYING,        ## 正常营业
	GAME_OVER,      ## 按 X 结束，展示本局收入
}

const MAX_ORDER_TICKETS := 24      # 待做小票队列上限（超出则丢弃最旧）
const VISIBLE_ORDER_COUNT := 4     # 订单看板默认显示条数

var hub_return_position: Vector2 = Vector2.ZERO  # 从分区回主场景时的落点
var has_hub_return: bool = false               # 是否已记录回城坐标
var player_money: float = 0.0                  # 本局累计收入（美元）
var session_phase: int = SessionPhase.WAITING_START
var last_session_earnings: float = 0.0        # 上一局结束时收入（结算界面显示）

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

var _customers: Dictionary = {}       # customer_id -> { id, layers, phase }
var _walk_in_queue: Array[int] = []   # 等待进店的顾客 id（FIFO）
var _pickup_queue: Array[int] = []    # 已点单、等待取餐的顾客 id（队首先交餐）
var _spawn_countdown: float = 0.0     # 距下次刷客剩余秒数
var _next_customer_id: int = 1
var _counter_busy: bool = false
var _active_counter_customer_id: int = -1  # 当前占用柜台的顾客；-1 表示空闲
## 已点单待做队列（FIFO）：{ "id", "customer_id", "layers" }
var _order_tickets: Array = []
var _next_ticket_id: int = 1


func _ready() -> void:
	_spawn_countdown = randf_range(5.0, 12.0)
	set_process(true)
	session_phase = SessionPhase.WAITING_START
	session_changed.emit(session_phase)


## 是否处于可操作的一局游戏中。
func is_session_active() -> bool:
	return session_phase == SessionPhase.PLAYING


## 按 E 开始新一局：清空状态并回到主场景。
func start_session() -> void:
	reset_runtime_state()
	session_phase = SessionPhase.PLAYING
	session_changed.emit(session_phase)
	_go_to_main_scene()


## 按 X 结束本局：记录收入并进入结算界面。
func end_session() -> void:
	if session_phase != SessionPhase.PLAYING:
		return
	last_session_earnings = OrderScoring.round_money(player_money)
	session_phase = SessionPhase.GAME_OVER
	session_changed.emit(session_phase)
	_go_to_main_scene()


## 清空本局玩法数据（顾客、队列、案板、收入等）。
func reset_runtime_state() -> void:
	player_money = 0.0
	last_session_earnings = 0.0
	cooked_patty_doneness_list.clear()
	last_cooked_doneness = -1
	finished_burgers.clear()
	assembly_plate_layers.clear()
	grill_patty_snapshots.clear()
	_grill_left_at_msec = -1
	_customers.clear()
	_walk_in_queue.clear()
	_pickup_queue.clear()
	_counter_busy = false
	_active_counter_customer_id = -1
	_order_tickets.clear()
	_next_customer_id = 1
	_next_ticket_id = 1
	has_hub_return = false
	_reset_spawn_timer()
	cooked_patties_changed.emit()
	finished_burgers_changed.emit()
	order_tickets_changed.emit()
	pickup_queue_changed.emit()
	money_changed.emit(0.0, 0.0, true)


func _go_to_main_scene() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var current := tree.current_scene
	if current != null and current.scene_file_path == MAIN_SCENE:
		return
	tree.change_scene_to_file(MAIN_SCENE)


## 进入收银区时若尚无顾客，立即刷一位以便排队流程能跑起来。
func ensure_customer_presence() -> void:
	if not is_session_active():
		return
	if not _customers.is_empty():
		return
	_try_spawn_customer()
	_reset_spawn_timer()


## 定时尝试刷出新顾客。
func _process(delta: float) -> void:
	if not is_session_active():
		return
	_spawn_countdown -= delta
	if _spawn_countdown > 0.0:
		return
	_try_spawn_customer()
	_reset_spawn_timer()


## 熟肉队列当前块数。
func get_cooked_count() -> int:
	return cooked_patty_doneness_list.size()


## 与列表长度一致，供旧代码读取
var cooked_patty_count: int:
	get:
		return cooked_patty_doneness_list.size()


## 熟肉区是否还能入库。
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


## 成品盘当前汉堡数量。
func get_finished_count() -> int:
	return finished_burgers.size()


## 成品盘是否还有空位。
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


## 最近一次入库肉饼的熟度中文标签。
func get_last_doneness_label() -> String:
	return get_doneness_label(last_cooked_doneness)


## 将 Patty.Doneness 整型转为中文标签。
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


## 离开煎肉区时保存各槽肉饼快照。
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


## 记录从主场景进入分区前的站立位置。
func save_hub_return(position: Vector2) -> void:
	hub_return_position = position
	has_hub_return = true


## 回到主场景并落点后清除回城记录。
func clear_hub_return() -> void:
	has_hub_return = false


## 持久化组装案板当前层（离开组装区时）。
func save_assembly_plate(layers: Array) -> void:
	assembly_plate_layers.clear()
	for layer in layers:
		if layer is Dictionary:
			assembly_plate_layers.append(layer.duplicate())


## 清空案板存档。
func clear_assembly_plate() -> void:
	assembly_plate_layers.clear()


## 读取案板层副本（进入组装区时恢复用）。
func get_assembly_plate_layers() -> Array:
	var copy: Array = []
	for layer in assembly_plate_layers:
		if layer is Dictionary:
			copy.append(layer.duplicate())
	return copy


## 重置下次刷客倒计时（随机区间）。
func _reset_spawn_timer() -> void:
	_spawn_countdown = randf_range(CUSTOMER_SPAWN_MIN_SEC, CUSTOMER_SPAWN_MAX_SEC)


## 在人数/队列未满时生成新顾客并加入 walk_in 队列。
func _try_spawn_customer() -> void:
	if not is_session_active():
		return
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


## 当前存活顾客 id 列表。
func get_all_customer_ids() -> Array:
	return _customers.keys()


## 查询顾客阶段；不存在返回 -1。
func get_customer_phase(customer_id: int) -> int:
	var record = _customers.get(customer_id)
	if record == null:
		return -1
	return record.get("phase", -1)


## 更新顾客阶段。
func set_customer_phase(customer_id: int, phase: int) -> void:
	var record = _customers.get(customer_id)
	if record == null:
		return
	record["phase"] = phase


## 复制该顾客的订单层数据。
func get_customer_layers(customer_id: int) -> Array:
	var record = _customers.get(customer_id)
	if record == null:
		return []
	var copy: Array = []
	for layer in record.get("layers", []):
		if layer is Dictionary:
			copy.append(layer.duplicate())
	return copy


## 取餐队列 id 副本（队首先交餐）。
func get_pickup_queue() -> Array:
	return _pickup_queue.duplicate()


## 从 walk_in 队首取出一位 PENDING 顾客 id；-1 表示无人可进店。
func pop_next_walk_in() -> int:
	while not _walk_in_queue.is_empty():
		var customer_id: int = _walk_in_queue.pop_front()
		if not _customers.has(customer_id):
			continue
		if get_customer_phase(customer_id) == CustomerPhase.PENDING:
			return customer_id
	return -1


## 将顾客插回 walk_in 队首（柜台占用失败时重试）。
func push_walk_in_front(customer_id: int) -> void:
	if customer_id in _walk_in_queue:
		_walk_in_queue.erase(customer_id)
	_walk_in_queue.insert(0, customer_id)


## 柜台是否正被某位顾客占用。
func is_counter_busy() -> bool:
	return _counter_busy


## 当前占用柜台的顾客 id；-1 表示空闲。
func get_active_counter_customer_id() -> int:
	return _active_counter_customer_id


## 尝试独占柜台；已被占用时返回 false。
func claim_counter(customer_id: int) -> bool:
	if _counter_busy:
		return false
	_counter_busy = true
	_active_counter_customer_id = customer_id
	return true


## 释放柜台占用。
func release_counter() -> void:
	_counter_busy = false
	_active_counter_customer_id = -1


## 仅当指定顾客占用柜台时才释放。
func release_counter_if(customer_id: int) -> void:
	if _active_counter_customer_id == customer_id:
		release_counter()


## 点单完成：入取餐队尾并登记订单小票；返回队列下标。
func enqueue_pickup(customer_id: int) -> int:
	if customer_id in _pickup_queue:
		return _pickup_queue.find(customer_id)
	_pickup_queue.append(customer_id)
	register_order_ticket(customer_id)
	customer_ordered.emit(customer_id)
	pickup_queue_changed.emit()
	return _pickup_queue.size() - 1


## 顾客点单完成：写入待做订单队列（队尾）。
func register_order_ticket(customer_id: int) -> void:
	var layers := get_customer_layers(customer_id)
	if layers.is_empty():
		return
	var copy: Array = []
	for layer in layers:
		if layer is Dictionary:
			copy.append(layer.duplicate())
	_order_tickets.append({
		"id": _next_ticket_id,
		"customer_id": customer_id,
		"layers": copy,
	})
	_next_ticket_id += 1
	while _order_tickets.size() > MAX_ORDER_TICKETS:
		_order_tickets.pop_front()
	order_tickets_changed.emit()


## 队首起最多 count 条（时间先到先显示）。
func get_order_tickets_head(count: int = VISIBLE_ORDER_COUNT) -> Array:
	var n := mini(count, _order_tickets.size())
	if n <= 0:
		return []
	var slice: Array = []
	for i in range(n):
		slice.append(_order_tickets[i].duplicate(true))
	return slice


## 待做订单小票总数。
func get_order_ticket_count() -> int:
	return _order_tickets.size()


## 交餐成功后移除该顾客的订单小票（队首对齐 FIFO）。
func remove_order_ticket_for_customer(customer_id: int) -> void:
	for i in _order_tickets.size():
		if _order_tickets[i].get("customer_id") == customer_id:
			_order_tickets.remove_at(i)
			order_tickets_changed.emit()
			return


## 队首有顾客且成品盘非空时可交餐。
func can_deliver_pickup() -> bool:
	return not _pickup_queue.is_empty() and not finished_burgers.is_empty()


## 取餐队首顾客 id；-1 表示队列为空。
func get_front_pickup_customer_id() -> int:
	if _pickup_queue.is_empty():
		return -1
	return _pickup_queue[0]


## 向取餐队首交付成品汉堡（finished_burgers 队首），按订单评分结算收入。
func deliver_to_front_pickup_customer() -> int:
	if not is_session_active() or not can_deliver_pickup():
		return -1
	var customer_id: int = _pickup_queue[0]
	var order_layers := get_customer_layers(customer_id)
	var delivered_layers := _copy_burger_layers(finished_burgers[0])
	var payment_result := OrderScoring.calculate_payment(order_layers, delivered_layers)
	var pay: float = payment_result["amount"]
	player_money = OrderScoring.round_money(player_money + pay)
	money_changed.emit(player_money, pay, payment_result["perfect_match"])
	finished_burgers.pop_front()
	finished_burgers_changed.emit()
	_pickup_queue.pop_front()
	remove_order_ticket_for_customer(customer_id)
	_customers.erase(customer_id)
	if customer_id in _walk_in_queue:
		_walk_in_queue.erase(customer_id)
	pickup_queue_changed.emit()
	return customer_id


## 复制一份汉堡层列表供评分使用。
func _copy_burger_layers(burger: Variant) -> Array:
	var copy: Array = []
	if not burger is Array:
		return copy
	for layer in burger:
		if layer is Dictionary:
			copy.append(layer.duplicate())
	return copy
