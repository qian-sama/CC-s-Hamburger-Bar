## 订单页：从上到下显示汉堡顶 → 馅料 → 汉堡底。
extends Control
class_name OrderPanel

## 食材图标缩放
const ICON_SCALE := 2.0

@onready var _items_box: VBoxContainer = $Panel/Margin/VBox/ItemsBox


## 按顶→底顺序填充订单行并显示面板。
func show_order(layers: Array) -> void:
	_clear_items()
	for layer in OrderGenerator.layers_top_first(layers):
		if not layer is Dictionary:
			continue
		var type: int = layer.get("type", -1)
		var doneness: int = layer.get("doneness", -1)
		_add_row(type as IngredientDefs.Type, doneness)
	visible = true


## 隐藏面板并清空内容。
func hide_order() -> void:
	visible = false
	_clear_items()


## 添加一行：图标 + 食材名称。
func _add_row(ingredient_type: IngredientDefs.Type, doneness: int) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(24, 24)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var tex := IngredientDefs.get_stack_texture(ingredient_type, doneness)
	if tex:
		icon.texture = tex
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	row.add_child(icon)
	var label := Label.new()
	label.text = IngredientDefs.get_display_name(ingredient_type, doneness)
	label.add_theme_font_size_override("font_size", 10)
	row.add_child(label)
	_items_box.add_child(row)


## 移除 ItemsBox 下所有子节点。
func _clear_items() -> void:
	for child in _items_box.get_children():
		child.queue_free()
