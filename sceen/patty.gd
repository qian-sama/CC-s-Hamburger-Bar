## 肉饼实体：负责煎制计时、熟度贴图、状态切换。
## 由 grill_work.gd 在铁板上生成；ON_GRILL 时累计 cook_time。
extends Area2D
class_name Patty

## 肉饼当前所处玩法状态
enum State {
	RAW,       ## 生肉（刚从冷藏区取出或掉落回冷藏）
	ON_GRILL,  ## 在铁板槽位上煎制中
	HELD,      ## 预留：手持（键盘玩法未使用）
	IN_HOLDER, ## 已送入熟肉区（随后通常会 queue_free）
}

## 对应 肉饼.tscn 里 grill 动画的帧序号（0~4）
enum Doneness {
	RAW = 0,       ## 0 熟
	THREE_MIN = 1, ## 约 1 分钟起：三分熟外观
	SEVEN_MIN = 2, ## 约 2 分钟起：七分熟外观
	WELL_DONE = 3, ## 3 分钟：全熟（可出锅）
	BURNT = 4,     ## 3 分 40 秒：焦糊
}

## 达到全熟、可出锅的时间（秒）
const COOK_DONE_TIME := 180.0
## 超过此时间变为焦肉饼（秒）
const COOK_BURNT_TIME := 220.0
## 外观阶段分界：0熟 → 3分 → 7分 → 全熟（秒）
const STAGE_BOUNDARIES := [0.0, 60.0, 120.0, COOK_DONE_TIME]

signal doneness_changed(doneness: Doneness)
signal became_ready      ## 首次达到 COOK_DONE_TIME
signal became_burnt       ## 首次达到 COOK_BURNT_TIME
signal state_changed(state: State)

## 煎制计时倍率（调试时可由 grill_work 设为较大值）
@export var time_scale: float = 1.0

@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D

var state: State = State.RAW:
	set(value):
		if state == value:
			return
		state = value
		state_changed.emit(state)
		# 仅在铁板上才每帧累加 cook_time
		_update_process_mode()

## 在铁板上的累计煎制时间（秒）
var cook_time: float = 0.0:
	set(value):
		cook_time = maxf(value, 0.0)
		_apply_visual()

## 当前占用的铁板槽位；-1 表示不在板上
var slot_index: int = -1

var doneness: Doneness = Doneness.RAW:
	set(value):
		if doneness == value:
			return
		doneness = value
		if _sprite:
			_sprite.frame = value
		doneness_changed.emit(doneness)

var _was_ready: bool = false
var _was_burnt: bool = false


func _ready() -> void:
	input_pickable = false
	_update_process_mode()
	_apply_visual()


func _process(delta: float) -> void:
	if state != State.ON_GRILL:
		return
	cook_time += delta * time_scale
	_check_milestones()


## 是否已全熟且未焦
func is_ready() -> bool:
	return cook_time >= COOK_DONE_TIME and doneness != Doneness.BURNT


func is_burnt() -> bool:
	return cook_time >= COOK_BURNT_TIME


## 是否允许从铁板取走（三分 / 七分 / 全熟 / 焦，不含 0 熟生肉）
func can_take_from_grill() -> bool:
	return state == State.ON_GRILL and doneness >= Doneness.THREE_MIN


## 进入熟肉区后冻结外观与计时（须已进入场景树，否则请用 setup_cooked_display）
func freeze_for_holder() -> void:
	setup_cooked_display(doneness)


## 熟肉区 / 组装区展示：固定熟度贴图，不再按 cook_time 重算
func setup_cooked_display(saved_doneness: Doneness) -> void:
	place_in_holder()
	set_process(false)
	doneness = saved_doneness
	cook_time = _cook_time_for_doneness(saved_doneness)
	_apply_holder_visual()


func _apply_holder_visual() -> void:
	if _sprite == null:
		return
	_sprite.stop()
	_sprite.animation = &"grill"
	_sprite.frame = doneness


static func _cook_time_for_doneness(d: Doneness) -> float:
	match d:
		Doneness.BURNT:
			return COOK_BURNT_TIME
		Doneness.WELL_DONE:
			return COOK_DONE_TIME
		Doneness.SEVEN_MIN:
			return STAGE_BOUNDARIES[2]
		Doneness.THREE_MIN:
			return STAGE_BOUNDARIES[1]
		_:
			return 0.0


## 是否允许放到铁板空槽（新生肉）
func can_place_on_grill() -> bool:
	return state == State.RAW


## 放入铁板槽位，开始煎制计时
func start_grilling(grill_slot: int) -> void:
	slot_index = grill_slot
	state = State.ON_GRILL


func stop_grilling() -> void:
	slot_index = -1


## 被鼠标抓起（若之前在板上则暂停该槽占用）
func pick_up() -> void:
	if state == State.ON_GRILL:
		stop_grilling()
	state = State.HELD


func place_in_holder() -> void:
	state = State.IN_HOLDER
	stop_grilling()


func reset_to_raw() -> void:
	state = State.RAW
	cook_time = 0.0
	slot_index = -1
	_was_ready = false
	_was_burnt = false
	doneness = Doneness.RAW


## 离开煎肉区前序列化（铁板上的肉饼）
func capture_grill_snapshot() -> Dictionary:
	return {
		"slot_index": slot_index,
		"cook_time": cook_time,
		"doneness": doneness,
		"was_ready": _was_ready,
		"was_burnt": _was_burnt,
		"time_scale": time_scale,
	}


## 回到煎肉区后恢复煎制进度；absent_seconds 为离开期间真实秒数 × time_scale 计入 cook_time
func load_grill_snapshot(data: Dictionary, absent_seconds: float = 0.0) -> void:
	time_scale = data.get("time_scale", 1.0)
	_was_ready = data.get("was_ready", false)
	_was_burnt = data.get("was_burnt", false)
	slot_index = data.get("slot_index", -1)
	state = State.ON_GRILL
	var base_time: float = data.get("cook_time", 0.0)
	cook_time = base_time + absent_seconds * time_scale
	if cook_time >= COOK_DONE_TIME:
		_was_ready = true
	if cook_time >= COOK_BURNT_TIME:
		_was_burnt = true


func get_doneness_label() -> String:
	match doneness:
		Doneness.RAW:
			return "生"
		Doneness.THREE_MIN:
			return "三分熟"
		Doneness.SEVEN_MIN:
			return "七分熟"
		Doneness.WELL_DONE:
			return "全熟"
		Doneness.BURNT:
			return "焦"
	return ""


func _update_process_mode() -> void:
	set_process(state == State.ON_GRILL)


func _check_milestones() -> void:
	if not _was_ready and cook_time >= COOK_DONE_TIME:
		_was_ready = true
		became_ready.emit()
	if not _was_burnt and cook_time >= COOK_BURNT_TIME:
		_was_burnt = true
		became_burnt.emit()


## 根据 cook_time 切换 AnimatedSprite2D 帧
func _apply_visual() -> void:
	if state == State.IN_HOLDER:
		_apply_holder_visual()
		return
	var next := _doneness_from_cook_time()
	doneness = next
	if _sprite == null:
		return
	_sprite.stop()
	_sprite.frame = next
	_sprite.animation = &"grill"


func _doneness_from_cook_time() -> Doneness:
	if state == State.RAW and cook_time <= 0.0:
		return Doneness.RAW
	if cook_time >= COOK_BURNT_TIME:
		return Doneness.BURNT
	if cook_time >= STAGE_BOUNDARIES[3]:
		return Doneness.WELL_DONE
	if cook_time >= STAGE_BOUNDARIES[2]:
		return Doneness.SEVEN_MIN
	if cook_time >= STAGE_BOUNDARIES[1]:
		return Doneness.THREE_MIN
	return Doneness.RAW
