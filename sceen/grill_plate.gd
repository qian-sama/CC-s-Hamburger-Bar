## 铁板：2 行 × 4 列共 8 槽，负责放置、按列取肉与空槽查询。
extends Node2D
class_name GrillPlate

const COLUMNS := 4
const ROWS := 2
const MAX_PATTIES := 8

var _slots: Array[GrillSlot] = []


func _ready() -> void:
	_collect_slots()


func _collect_slots() -> void:
	_slots.clear()
	for child in get_children():
		if child is GrillSlot:
			_slots.append(child)
	_slots.sort_custom(func(a: GrillSlot, b: GrillSlot) -> bool:
		return a.slot_index < b.slot_index
	)


func patty_count() -> int:
	var count := 0
	for slot in _slots:
		if not slot.is_empty():
			count += 1
	return count


func is_full() -> bool:
	return patty_count() >= MAX_PATTIES


## 按槽位 0→7 找第一个空槽（先上排后下排）。
func find_first_empty_slot() -> int:
	for i in MAX_PATTIES:
		var slot := get_slot(i)
		if slot != null and slot.is_empty():
			return i
	return -1


func get_slot(index: int) -> GrillSlot:
	for slot in _slots:
		if slot.slot_index == index:
			return slot
	return null


static func column_row_to_slot(column: int, row: int) -> int:
	return column + row * COLUMNS


static func slot_to_column(slot_index: int) -> int:
	return slot_index % COLUMNS


static func slot_to_row(slot_index: int) -> int:
	return slot_index / COLUMNS


## 根据玩家 X 坐标选最近列（0~3）。
func get_column_from_global_x(global_x: float) -> int:
	var best_column := 0
	var best_dist := INF
	for col in COLUMNS:
		var top_slot := get_slot(column_row_to_slot(col, 0))
		if top_slot == null:
			continue
		var cx := top_slot.snap_global_position().x
		var dist := absf(global_x - cx)
		if dist < best_dist:
			best_dist = dist
			best_column = col
	return best_column


## 将生肉饼放入指定槽并开始煎制。
func place_patty(patty: Patty, slot_index: int) -> bool:
	if not patty.can_place_on_grill():
		return false
	var slot := get_slot(slot_index)
	if slot == null or not slot.is_empty():
		return false
	slot.assign_patty(patty)
	patty.global_position = slot.snap_global_position()
	patty.z_index = 1
	patty.start_grilling(slot_index)
	return true


## 从指定列、行取走肉饼（row 0=上层 I，row 1=下层 O）。
func take_from_column(column: int, row: int) -> Patty:
	var slot_index := column_row_to_slot(column, row)
	var slot := get_slot(slot_index)
	if slot == null or slot.is_empty():
		return null
	var patty := slot.patty
	slot.clear_patty()
	patty.stop_grilling()
	return patty


## 未熟肉饼放回原来的槽（不检查 RAW 状态）。
func restore_patty_to_slot(patty: Patty, slot_index: int) -> bool:
	var slot := get_slot(slot_index)
	if slot == null or not slot.is_empty():
		return false
	slot.assign_patty(patty)
	patty.global_position = slot.snap_global_position()
	patty.z_index = 1
	patty.start_grilling(slot_index)
	return true
