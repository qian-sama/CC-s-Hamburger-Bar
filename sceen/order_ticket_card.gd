## 单张订单小票：Panel 背景随内容拉高，食材紧挨且始终在纸内。
extends PanelContainer
class_name OrderTicketCard

const BG_TEXTURE := preload("res://游戏素材/场景/订单背景.png")
## 小票最小宽度（像素）
const TICKET_WIDTH := 56.0
const MIN_HEIGHT := 40.0
## 单行食材图标边长
const ICON_PX := 7.0

@onready var _items: VBoxContainer = $Items


func _ready() -> void:
	_apply_panel_style()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN


## 按顶→底顺序填充食材图标，并延迟适配 Panel 高度。
func set_layers(layers: Array) -> void:
	var items := _items_box()
	if items == null:
		push_warning("OrderTicketCard: Items 节点未就绪")
		return
	for child in items.get_children():
		child.queue_free()
	var normalized := OrderGenerator.normalize_layers_for_display(layers)
	for layer in OrderGenerator.layers_top_first(normalized):
		if not layer is Dictionary:
			continue
		var type: int = layer.get("type", -1)
		var doneness: int = layer.get("doneness", -1)
		var ingredient_type := type as IngredientDefs.Type
		var tex := IngredientDefs.get_stack_texture(ingredient_type, doneness)
		if tex == null and ingredient_type == IngredientDefs.Type.BUN_TOP:
			tex = preload("res://游戏素材/食材/汉堡上皮.png") as Texture2D
		if tex == null:
			continue
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(ICON_PX, ICON_PX)
		icon.size = Vector2(ICON_PX, ICON_PX)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.texture = tex
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		items.add_child(icon)
	call_deferred("_fit_panel_to_content")


## 使用订单背景图作为 Panel 样式并设置内边距。
func _apply_panel_style() -> void:
	var style := StyleBoxTexture.new()
	style.texture = BG_TEXTURE
	style.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	style.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	style.content_margin_left = 8
	style.content_margin_top = 7
	style.content_margin_right = 8
	style.content_margin_bottom = 7
	add_theme_stylebox_override("panel", style)


## 根据 Items 内容高度设置 custom_minimum_size。
func _fit_panel_to_content() -> void:
	var items := _items_box()
	if items == null:
		return
	var content_min := items.get_combined_minimum_size()
	var style := get_theme_stylebox("panel") as StyleBoxTexture
	var pad_h := 14.0
	var pad_w := 16.0
	if style:
		pad_h = style.get_content_margin(SIDE_TOP) + style.get_content_margin(SIDE_BOTTOM)
		pad_w = style.get_content_margin(SIDE_LEFT) + style.get_content_margin(SIDE_RIGHT)
	var height := maxf(MIN_HEIGHT, content_min.y + pad_h)
	var width := maxf(TICKET_WIDTH, content_min.x + pad_w)
	custom_minimum_size = Vector2(width, height)
	size = custom_minimum_size


## 安全获取 Items 容器（@onready 未就绪时回退查找）。
func _items_box() -> VBoxContainer:
	if _items != null:
		return _items
	return get_node_or_null("Items") as VBoxContainer
