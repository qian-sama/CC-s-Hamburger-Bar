## 组装台汉堡叠层：底包 → 馅料 → 顶包；重做时清空（已消耗肉饼不返还）。
extends Node2D
class_name BurgerStack

const MAX_FILL_LAYERS := 12
const STACK_STEP := 3.88

@export var layer_scale: float = 2.5

@onready var _layers_root: Node2D = $Layers

var _layers: Array[Dictionary] = []
var _has_bottom: bool = false
var _has_top: bool = false


func has_bottom() -> bool:
	return _has_bottom


func has_top() -> bool:
	return _has_top


func is_complete() -> bool:
	return _has_bottom and _has_top


func is_empty() -> bool:
	return _layers.is_empty()


## 当前案板层快照（含未完成汉堡）。
func get_layers_copy() -> Array:
	var copy: Array = []
	for layer in _layers:
		copy.append(layer.duplicate())
	return copy


## 从 GameState 恢复；肉饼已在之前组装时从队列取出，不再扣熟肉。
func restore_from_layers(layers: Array) -> void:
	redo_burger()
	for layer in layers:
		if not layer is Dictionary:
			continue
		var type: int = layer.get("type", -1)
		var doneness: int = layer.get("doneness", -1)
		if type == IngredientDefs.Type.BUN_BOTTOM:
			_has_bottom = true
		elif type == IngredientDefs.Type.BUN_TOP:
			_has_top = true
		if not _append_layer(type as IngredientDefs.Type, doneness):
			push_warning("BurgerStack: 恢复案板失败 type=%s" % type)
			redo_burger()
			return


## 已封顶：复制层数据（不清空组装台）。
func get_completed_layers_copy() -> Array:
	if not is_complete():
		return []
	var copy: Array = []
	for layer in _layers:
		copy.append(layer.duplicate())
	return copy


## 空栈放底；有底未封顶放顶；否则失败。
func try_bottom_or_top() -> bool:
	if not _has_bottom:
		return _place_bun(IngredientDefs.Type.BUN_BOTTOM)
	if not _has_top:
		return _place_bun(IngredientDefs.Type.BUN_TOP)
	return false


## 需已有底且未封顶；肉饼从 GameState FIFO 取出。
func try_add_ingredient(ingredient_type: IngredientDefs.Type) -> bool:
	if not _has_bottom or _has_top:
		return false
	if ingredient_type == IngredientDefs.Type.BUN_BOTTOM \
			or ingredient_type == IngredientDefs.Type.BUN_TOP:
		return false
	if _fill_layer_count() >= MAX_FILL_LAYERS:
		return false
	if ingredient_type == IngredientDefs.Type.PATTI:
		var game_state := _get_game_state()
		if game_state == null:
			return false
		var doneness := game_state.take_next_cooked_patty()
		if doneness < Patty.Doneness.THREE_MIN:
			return false
		return _append_layer(ingredient_type, doneness)
	return _append_layer(ingredient_type, -1)


## 丢弃当前汉堡；已 take 的肉饼视为销毁，不归还队列。
func redo_burger() -> void:
	for child in _layers_root.get_children():
		child.queue_free()
	_layers.clear()
	_has_bottom = false
	_has_top = false


func _place_bun(bun_type: IngredientDefs.Type) -> bool:
	if bun_type == IngredientDefs.Type.BUN_BOTTOM:
		if _has_bottom:
			return false
		_has_bottom = true
	elif bun_type == IngredientDefs.Type.BUN_TOP:
		if not _has_bottom or _has_top:
			return false
		_has_top = true
	else:
		return false
	return _append_layer(bun_type, -1)


func _append_layer(type: IngredientDefs.Type, doneness: int) -> bool:
	var texture := IngredientDefs.get_stack_texture(type, doneness)
	if texture == null:
		if type == IngredientDefs.Type.BUN_BOTTOM:
			_has_bottom = false
		elif type == IngredientDefs.Type.BUN_TOP:
			_has_top = false
		return false
	_layers.append({"type": type, "doneness": doneness})
	var index := _layers.size() - 1
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.scale = Vector2(layer_scale, layer_scale)
	sprite.position = Vector2(0, -index * STACK_STEP)
	sprite.z_index = index
	_layers_root.add_child(sprite)
	return true


func _fill_layer_count() -> int:
	var count := 0
	for layer in _layers:
		var t: int = layer["type"]
		if t != IngredientDefs.Type.BUN_BOTTOM and t != IngredientDefs.Type.BUN_TOP:
			count += 1
	return count


func _get_game_state() -> GameStateService:
	return get_tree().root.get_node_or_null("GameState") as GameStateService
