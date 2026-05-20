## 组装区底部食材轮播：SpriteFrames 循环播放；熟肉盘空时不含肉饼帧。
extends Control
class_name IngredientCarousel

const ANIM_NAME := &"cycle"

## 每一帧停留秒数（越大越慢，一帧一帧切换）
@export var frame_duration: float = 1.0
@export var sprite_scale: float = 2.5

@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D

var _ingredient_order: Array[IngredientDefs.Type] = []  # 当前轮播帧顺序
var _frozen: bool = false  # true 时停止轮播（如选中肉饼后）


func _ready() -> void:
	if _sprite == null:
		_sprite = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if _sprite == null:
		push_error("IngredientCarousel: 缺少子节点 AnimatedSprite2D")
		return
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.scale = Vector2(sprite_scale, sprite_scale)
	var game_state := _get_game_state()
	if game_state and not game_state.cooked_patties_changed.is_connected(_on_cooked_patties_changed):
		game_state.cooked_patties_changed.connect(_on_cooked_patties_changed)
	call_deferred("_rebuild_and_play")


## 熟肉队列变化时重建轮播（未 freeze 时）。
func _on_cooked_patties_changed() -> void:
	if _frozen:
		return
	_rebuild_and_play()


## 按是否有熟肉重建 SpriteFrames 并开始循环播放。
func _rebuild_and_play() -> void:
	if _sprite == null:
		return
	_ingredient_order = IngredientDefs.build_carousel_order(_has_cooked_patty())
	var peek_doneness := _peek_doneness()
	var frames := SpriteFrames.new()
	frames.add_animation(ANIM_NAME)
	frames.set_animation_loop(ANIM_NAME, true)
	frames.set_animation_speed(ANIM_NAME, 1.0)
	for ingredient_type in _ingredient_order:
		var texture := IngredientDefs.get_carousel_texture(ingredient_type, peek_doneness)
		if texture != null:
			frames.add_frame(ANIM_NAME, texture, frame_duration)
	if frames.get_frame_count(ANIM_NAME) == 0:
		_sprite.visible = false
		_sprite.stop()
		return
	_sprite.visible = true
	_sprite.sprite_frames = frames
	_sprite.play(ANIM_NAME)
	_center_sprite()


## 返回当前停在哪一帧对应的食材类型。
func get_current_ingredient() -> IngredientDefs.Type:
	if _ingredient_order.is_empty() or _sprite == null:
		return IngredientDefs.Type.PICKLE
	var index := clampi(_sprite.frame, 0, _ingredient_order.size() - 1)
	return _ingredient_order[index]


## 停在当前帧，不再自动切换。
func freeze_on_current() -> void:
	if _sprite == null:
		return
	_frozen = true
	_sprite.stop()


## 恢复自动轮播。
func resume_cycle() -> void:
	_frozen = false
	_rebuild_and_play()


## 熟肉区是否有肉（决定轮播是否含 PATTI 帧）。
func _has_cooked_patty() -> bool:
	var game_state := _get_game_state()
	return game_state != null and game_state.get_cooked_count() > 0


## 预览队首肉饼熟度（用于肉饼轮播帧贴图）。
func _peek_doneness() -> int:
	var game_state := _get_game_state()
	if game_state == null:
		return -1
	return game_state.peek_next_cooked_doneness()


## 将精灵居中于 Control 区域。
func _center_sprite() -> void:
	if _sprite == null:
		return
	_sprite.position = size * 0.5


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_node_ready():
		_center_sprite()


func _get_game_state() -> GameStateService:
	return get_tree().root.get_node_or_null("GameState") as GameStateService
