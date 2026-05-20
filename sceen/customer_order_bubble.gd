## 顾客身旁订单：背景放大显示，按组装顺序从下往上逐条显示食材。
extends Node2D
class_name CustomerOrderBubble

signal reveal_finished  # 逐层写出完成（含顶包停留）

const BG_TEXTURE := preload("res://游戏素材/场景/订单背景.png")
## 与顾客.tscn 中 AnimatedSprite2D 帧尺寸、根节点 scale 一致
const CUSTOMER_FRAME_PX := 16.0
const CUSTOMER_NODE_SCALE := 2.0
## 订单背景相对顾客精灵的放大倍数
const ORDER_SIZE_MULT := 3.2
## 每层食材写出间隔（秒）
const LAYER_REVEAL_SEC := 0.72
## 单条食材图标目标边长（像素）
const ICON_PX := 4.0
## 多条食材纵向间距（像素）
const LAYER_STEP_PX := 4.0
## 食材列底部 Y（自下往上叠）
const ITEMS_BOTTOM_Y := 14.0
## 食材列顶部 Y（超出时压缩 step）
const ITEMS_TOP_Y := -10.0

## 相对顾客根节点的偏移（身旁位置）
@export var side_offset: Vector2 = Vector2(28, -24)

@onready var _bg: Sprite2D = $Background
@onready var _items_root: Node2D = $Items

var _layers: Array = []              # 规范化后的订单层
var _reveal_index: int = 0           # 下一条待写出的层索引
var _reveal_generation: int = 0      # 取消/重开 reveal 时递增，防止旧定时器回调


func _ready() -> void:
	_bg.texture = BG_TEXTURE
	_bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_fit_background_scale()
	_items_root.z_index = 1
	visible = false


## 逐层写出订单（底→顶）；空订单立即 emit reveal_finished。
func start_reveal(layers: Array) -> void:
	_cancel_reveal()
	_clear_items()
	_layers = OrderGenerator.normalize_layers_for_display(layers)
	if _layers.is_empty():
		reveal_finished.emit()
		return
	position = side_offset
	visible = true
	_reveal_index = 0
	_reveal_next_layer()


## 一次性显示完整订单（不播放写出动画）。
func show_complete(layers: Array) -> void:
	_cancel_reveal()
	_clear_items()
	_layers = OrderGenerator.normalize_layers_for_display(layers)
	for layer in _layers:
		_append_item_sprite(layer)
	position = side_offset
	visible = not _layers.is_empty()
	reveal_finished.emit()


## 隐藏气泡并清空内容。
func hide_bubble() -> void:
	_cancel_reveal()
	_clear_items()
	_layers.clear()
	visible = false


## 写出下一条食材层；全部写完后 schedule reveal_finished。
func _reveal_next_layer() -> void:
	if _reveal_index >= _layers.size():
		reveal_finished.emit()
		return
	_append_item_sprite(_layers[_reveal_index])
	_reveal_index += 1
	if _reveal_index >= _layers.size():
		_schedule_reveal_finished()
		return
	var gen := _reveal_generation
	get_tree().create_timer(LAYER_REVEAL_SEC).timeout.connect(
		func() -> void:
			if gen == _reveal_generation:
				_reveal_next_layer(),
		CONNECT_ONE_SHOT
	)


## 顶包写出后再等一拍，避免立刻隐藏导致看不到顶包。
func _schedule_reveal_finished() -> void:
	var gen := _reveal_generation
	get_tree().create_timer(LAYER_REVEAL_SEC).timeout.connect(
		func() -> void:
			if gen == _reveal_generation:
				reveal_finished.emit(),
		CONNECT_ONE_SHOT
	)


## 根据层数据创建一条食材 Sprite 并重新布局。
func _append_item_sprite(layer: Dictionary) -> void:
	var type: int = layer.get("type", -1)
	var doneness: int = layer.get("doneness", -1)
	var ingredient_type := type as IngredientDefs.Type
	var tex := IngredientDefs.get_stack_texture(ingredient_type, doneness)
	if tex == null and ingredient_type == IngredientDefs.Type.BUN_TOP:
		tex = preload("res://游戏素材/食材/汉堡上皮.png") as Texture2D
	if tex == null:
		push_warning("CustomerOrderBubble: 缺少贴图 type=%s" % type)
		return
	var sprite := Sprite2D.new()
	sprite.texture = tex
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var tex_size := tex.get_size()
	var icon_scale := ICON_PX / maxf(tex_size.x, tex_size.y)
	sprite.scale = Vector2(icon_scale, icon_scale)
	sprite.z_index = _items_root.get_child_count()
	_items_root.add_child(sprite)
	_relayout_items()


## 按写出顺序自下往上叠放：第 0 条在底，最后一条（汉堡顶）在最上。
func _relayout_items() -> void:
	var children := _items_root.get_children()
	var count := children.size()
	if count == 0:
		return
	var step := LAYER_STEP_PX
	var max_stack := ITEMS_BOTTOM_Y - ITEMS_TOP_Y
	if count > 1 and (count - 1) * step > max_stack:
		step = max_stack / float(count - 1)
	for i in range(count):
		(children[i] as Node2D).position.y = ITEMS_BOTTOM_Y - float(i) * step


## 按顾客精灵尺寸缩放订单背景，抵消父节点 scale。
func _fit_background_scale() -> void:
	var tex_size := BG_TEXTURE.get_size()
	if tex_size.x <= 0 or tex_size.y <= 0:
		return
	var parent_scale := 1.0
	var parent_node := get_parent()
	if parent_node is Node2D:
		parent_scale = (parent_node as Node2D).scale.x
	var target_px := CUSTOMER_FRAME_PX * CUSTOMER_NODE_SCALE * ORDER_SIZE_MULT
	var fit := target_px / maxf(tex_size.x, tex_size.y)
	_bg.scale = Vector2(fit, fit) / parent_scale


## 移除 Items 下所有精灵。
func _clear_items() -> void:
	for child in _items_root.get_children():
		child.queue_free()


## 递增 generation，使进行中的 reveal 定时器失效。
func _cancel_reveal() -> void:
	_reveal_generation += 1
