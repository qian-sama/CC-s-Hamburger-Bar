## 顾客：沿路径点行走、四向动画；点单时在身旁显示订单气泡。
extends Node2D
class_name CustomerActor

signal walk_finished       # 路径走完
signal order_reveal_finished  # 身旁订单气泡写出结束

const WALK_SPEED := 52.0
## 1~3 号位：背面
const QUEUE_FRONT_SLOTS_FACING := &"up_down back"
## 4~6 号位：正面
const QUEUE_BACK_SLOTS_FACING := &"up_down front"

@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var _order_bubble: CustomerOrderBubble = $CustomerOrderBubble

var customer_id: int = -1
var _walk_tween: Tween = null  # 当前段行走补间


## 绑定 GameState 中的顾客 id。
func setup(id: int) -> void:
	customer_id = id


## 瞬移到世界坐标（停止当前行走）。
func snap_to_world(world_pos: Vector2) -> void:
	_kill_walk_tween()
	if not is_inside_tree():
		return
	position = _world_to_local(world_pos)


## 按世界坐标路径点依次行走；空路径立即 emit walk_finished。
func walk_through_world(world_points: PackedVector2Array, speed: float = WALK_SPEED) -> void:
	if world_points.is_empty():
		walk_finished.emit()
		return
	if not is_inside_tree():
		call_deferred("walk_through_world", world_points, speed)
		return
	_kill_walk_tween()
	_walk_segment(world_points, 0, speed)


## 停止行走补间。
func stop_walking() -> void:
	_kill_walk_tween()


## 点单区：订单出现在身旁，按层从下往上逐条写出。
func begin_order_reveal(layers: Array) -> void:
	_face_for_counter_order()
	if not _order_bubble.reveal_finished.is_connected(_on_order_reveal_finished):
		_order_bubble.reveal_finished.connect(_on_order_reveal_finished, CONNECT_ONE_SHOT)
	_order_bubble.start_reveal(layers)


## 一次性显示完整订单（不播放写出动画）。
func show_order_complete(layers: Array) -> void:
	_face_for_counter_order()
	_order_bubble.show_complete(layers)


## 隐藏订单气泡并断开 reveal 信号。
func hide_order_bubble() -> void:
	if _order_bubble.reveal_finished.is_connected(_on_order_reveal_finished):
		_order_bubble.reveal_finished.disconnect(_on_order_reveal_finished)
	_order_bubble.hide_bubble()


func _on_order_reveal_finished() -> void:
	order_reveal_finished.emit()


## 到达柜台：面向右侧并停止动画。
func prepare_at_counter() -> void:
	_face_for_counter_order()


## 点单时固定面向右侧。
func _face_for_counter_order() -> void:
	_sprite.animation = &"right"
	_sprite.stop()
	_sprite.frame = 0


## pickup_slot_index：0=1号 … 5=6号；静止、不播放行走动画。
func set_queue_idle(pickup_slot_index: int) -> void:
	_kill_walk_tween()
	var facing: StringName = (
		QUEUE_FRONT_SLOTS_FACING if pickup_slot_index <= 2 else QUEUE_BACK_SLOTS_FACING
	)
	_sprite.animation = facing
	_sprite.stop()
	_sprite.frame = 0


func _exit_tree() -> void:
	_kill_walk_tween()
	hide_order_bubble()


## 世界坐标转本地坐标（相对父 Node2D）。
func _world_to_local(world_pos: Vector2) -> Vector2:
	var parent_node := get_parent()
	if parent_node is Node2D:
		return (parent_node as Node2D).to_local(world_pos)
	return world_pos


## 递归行走：当前 index 指向的路径点 → tween → 下一段。
func _walk_segment(points: PackedVector2Array, index: int, speed: float) -> void:
	if not is_inside_tree():
		return
	if index >= points.size():
		walk_finished.emit()
		return
	var target_world: Vector2 = points[index]
	var target_local := _world_to_local(target_world)
	var dist := position.distance_to(target_local)
	var duration := maxf(dist / speed, 0.08)
	_face_toward(target_world - global_position)
	_walk_tween = create_tween()
	_walk_tween.tween_property(self, "position", target_local, duration)
	_walk_tween.finished.connect(
		func() -> void:
			if is_instance_valid(self) and is_inside_tree():
				_walk_segment(points, index + 1, speed),
		CONNECT_ONE_SHOT
	)


## 根据位移方向播放四向行走动画。
func _face_toward(delta: Vector2) -> void:
	if delta.length_squared() < 1.0:
		return
	if absf(delta.x) >= absf(delta.y):
		_sprite.play("right" if delta.x > 0.0 else "left")
	else:
		_sprite.play("up_down front" if delta.y > 0.0 else "up_down back")


## 终止并清空当前行走 Tween。
func _kill_walk_tween() -> void:
	if _walk_tween != null and _walk_tween.is_valid():
		_walk_tween.kill()
	_walk_tween = null
