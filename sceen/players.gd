## 玩家角色：移动、四方向动画、交互提示与按 E 切换场景。
extends CharacterBody2D

# --- 节点引用（场景加载后自动获取）---
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D  # 人物精灵动画
@onready var interact_label: Label = $Label                       # 头顶「Press E」文字

# --- 移动与动画状态 ---
var direction: Vector2 = Vector2.ZERO              # 本帧输入方向（WASD）
var speed: int = 150                               # 移动速度（像素/秒）
var last_facing: StringName = &"up_down front"     # 上次朝向，站立时保持该方向帧
var _interact_zone: Area2D = null                  # 当前所在的交互区域（煎肉入口/出口等）


# ========== 交互区域（由 interact_zone.gd 调用）==========

## 走进某个交互区域时调用：记录区域并显示 Press E。
func enter_interact_zone(zone: Area2D) -> void:
	_interact_zone = zone
	show_interact_prompt()


## 离开交互区域时调用：若离开的是当前区域则隐藏提示。
func exit_interact_zone(zone: Area2D) -> void:
	if _interact_zone == zone:
		_interact_zone = null
		hide_interact_prompt()


## 显示头顶交互提示。
func show_interact_prompt() -> void:
	interact_label.visible = true


## 隐藏头顶交互提示。
func hide_interact_prompt() -> void:
	interact_label.visible = false


## 处理未消费的输入：在交互区内按 E 时触发该区域的场景切换。
func _unhandled_input(event: InputEvent) -> void:
	if _interact_zone == null:
		return
	if not event.is_action_pressed("Interact"):  # 项目输入映射里的 E 键
		return
	if not _interact_zone.has_method("interact"):
		return
	# 先标记输入已处理，再切场景（顺序不能反，否则切场景后 viewport 可能为 null）
	var viewport := get_viewport()
	if viewport:
		viewport.set_input_as_handled()
	_interact_zone.interact()


# ========== 移动（每物理帧）==========

func _physics_process(_delta: float) -> void:
	direction = Input.get_vector("Left", "Right", "Up", "Down")  # 合成方向向量
	velocity = direction * speed
	move_and_slide()
	update_animation(direction)


# ========== 动画 ==========

## 根据是否在移动，播放行走或站立（当前朝向第 0 帧）。
func update_animation(move_direction: Vector2) -> void:
	if move_direction == Vector2.ZERO:
		play_idle_animation()
	else:
		play_walk_animation(move_direction)


## 根据移动方向返回对应动画名（斜向时取绝对值更大的轴）。
func _get_facing_animation(move_direction: Vector2) -> StringName:
	if abs(move_direction.x) > abs(move_direction.y):
		return &"right" if move_direction.x > 0.0 else &"left"
	if move_direction.y > 0.0:
		return &"up_down front"   # 向下 = 正面
	return &"up_down back"        # 向上 = 背面


## 播放对应方向的行走循环动画。
func play_walk_animation(move_direction: Vector2) -> void:
	var anim_name := _get_facing_animation(move_direction)
	last_facing = anim_name
	if animated_sprite.animation != anim_name or not animated_sprite.is_playing():
		animated_sprite.play(anim_name)


## 站立：停在当前朝向动画的第 0 帧。
func play_idle_animation() -> void:
	if animated_sprite.animation != last_facing:
		animated_sprite.animation = last_facing
	animated_sprite.stop()
	animated_sprite.frame = 0
