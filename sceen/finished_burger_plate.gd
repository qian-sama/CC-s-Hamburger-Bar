## 成品盘：展示已封顶入库的汉堡，与 GameState.finished_burgers 同步。
extends Node2D
class_name FinishedBurgerPlate

const DISPLAY_SCALE := 1.2
const DISPLAY_STACK_STEP := 1.5

@onready var _display_root: Node2D = $DisplayedBurgers
@onready var _slot_markers: Node2D = $DisplaySlots

var _markers: Array[Marker2D] = []  # 按名称排序的展示槽位


func _ready() -> void:
	_collect_markers()
	var game_state := _get_game_state()
	if game_state and not game_state.finished_burgers_changed.is_connected(_on_finished_changed):
		game_state.finished_burgers_changed.connect(_on_finished_changed)
	sync_from_game_state()


## GameState 成品队列变化时刷新画面。
func _on_finished_changed() -> void:
	sync_from_game_state()


## 成品盘是否已达上限。
func is_full() -> bool:
	var game_state := _get_game_state()
	if game_state == null:
		return true
	return not game_state.can_add_finished_burger()


## 按 GameState.finished_burgers 重建所有槽位上的汉堡叠层。
func sync_from_game_state() -> void:
	_clear_display()
	var game_state := _get_game_state()
	if game_state == null:
		return
	for i in game_state.finished_burgers.size():
		_spawn_burger_visual(game_state.finished_burgers[i], i)


## 在指定槽位生成一份汉堡的叠层精灵。
func _spawn_burger_visual(layers: Array, slot_index: int) -> void:
	var burger_root := Node2D.new()
	_display_root.add_child(burger_root)
	if slot_index < _markers.size():
		burger_root.global_position = _markers[slot_index].global_position
	for i in layers.size():
		var layer = layers[i]
		if not layer is Dictionary:
			continue
		var type: int = layer.get("type", -1)
		var doneness: int = layer.get("doneness", -1)
		var texture := IngredientDefs.get_stack_texture(type as IngredientDefs.Type, doneness)
		if texture == null:
			continue
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.scale = Vector2(DISPLAY_SCALE, DISPLAY_SCALE)
		sprite.position = Vector2(0, -i * DISPLAY_STACK_STEP)
		sprite.z_index = i
		burger_root.add_child(sprite)


## 移除展示区所有汉堡节点。
func _clear_display() -> void:
	for child in _display_root.get_children():
		child.queue_free()


## 收集 DisplaySlots 下 Marker2D 并按名称排序。
func _collect_markers() -> void:
	_markers.clear()
	for child in _slot_markers.get_children():
		if child is Marker2D:
			_markers.append(child)
	_markers.sort_custom(func(a: Marker2D, b: Marker2D) -> bool:
		return a.name.naturalnocasecmp_to(b.name) < 0
	)


## 获取 autoload GameState 单例。
func _get_game_state() -> GameStateService:
	return get_tree().root.get_node_or_null("GameState") as GameStateService
