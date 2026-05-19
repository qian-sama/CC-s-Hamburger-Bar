## 成品盘：展示已封顶入库的汉堡，与 GameState.finished_burgers 同步。
extends Node2D
class_name FinishedBurgerPlate

const DISPLAY_SCALE := 1.2
const DISPLAY_STACK_STEP := 1.5

@onready var _display_root: Node2D = $DisplayedBurgers
@onready var _slot_markers: Node2D = $DisplaySlots

var _markers: Array[Marker2D] = []


func _ready() -> void:
	_collect_markers()
	var game_state := _get_game_state()
	if game_state and not game_state.finished_burgers_changed.is_connected(_on_finished_changed):
		game_state.finished_burgers_changed.connect(_on_finished_changed)
	sync_from_game_state()


func _on_finished_changed() -> void:
	sync_from_game_state()


func is_full() -> bool:
	var game_state := _get_game_state()
	if game_state == null:
		return true
	return not game_state.can_add_finished_burger()


func sync_from_game_state() -> void:
	_clear_display()
	var game_state := _get_game_state()
	if game_state == null:
		return
	for i in game_state.finished_burgers.size():
		_spawn_burger_visual(game_state.finished_burgers[i], i)


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


func _clear_display() -> void:
	for child in _display_root.get_children():
		child.queue_free()


func _collect_markers() -> void:
	_markers.clear()
	for child in _slot_markers.get_children():
		if child is Marker2D:
			_markers.append(child)
	_markers.sort_custom(func(a: Marker2D, b: Marker2D) -> bool:
		return a.name.naturalnocasecmp_to(b.name) < 0
	)


func _get_game_state() -> GameStateService:
	return get_tree().root.get_node_or_null("GameState") as GameStateService
