## 组装区：O 底/顶包，I 加料，P 成品盘，L 重做，E 回主场景。
extends Node2D

const CANT_DO_TEXT := "i can't do this!"
const CANT_DO_DURATION := 1.4

@onready var _burger_stack: BurgerStack = $AssemblyPlate/BurgerStack
@onready var _finished_plate: FinishedBurgerPlate = $FinishedPlate
@onready var _carousel: IngredientCarousel = $UI/BottomBar/IngredientCarousel
@onready var _cant_do_hint: Label = $AssemblyPlate/CantDoHint

var _cant_do_timer: float = 0.0  # 「不能做」提示剩余显示时间


func _ready() -> void:
	_restore_assembly_plate()


## 倒计时结束后隐藏 CantDoHint。
func _process(delta: float) -> void:
	if _cant_do_timer <= 0.0:
		return
	_cant_do_timer -= delta
	if _cant_do_timer <= 0.0:
		_cant_do_hint.visible = false


## 处理组装区按键：E 回主场景，O/I/P/L 对应包/料/成品/重做。
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	var game_state := _get_game_state()
	if game_state != null and not game_state.is_session_active():
		return
	var viewport := get_viewport()

	if event.is_action_pressed("Interact"):
		if viewport:
			viewport.set_input_as_handled()
		_exit_to_hub()
		return

	if event.is_action_pressed("TakePattyBottom"):
		if _burger_stack.try_bottom_or_top():
			if viewport:
				viewport.set_input_as_handled()
		else:
			_show_cant_do()
		return

	if event.is_action_pressed("TakePattyTop"):
		var ingredient := _carousel.get_current_ingredient()
		if _burger_stack.try_add_ingredient(ingredient):
			if viewport:
				viewport.set_input_as_handled()
		else:
			_show_cant_do()
		return

	if event.is_action_pressed("PlacePatty"):
		if _try_place_on_finished_plate():
			if viewport:
				viewport.set_input_as_handled()
		else:
			_show_cant_do()
		return

	if event.is_action_pressed("RedoBurger"):
		_burger_stack.redo_burger()
		_clear_assembly_plate_state()
		_carousel.resume_cycle()
		if viewport:
			viewport.set_input_as_handled()


## 汉堡已封顶且成品盘有空位时，入库并清空案板。
func _try_place_on_finished_plate() -> bool:
	if not _burger_stack.is_complete():
		return false
	if _finished_plate.is_full():
		return false
	var layers := _burger_stack.get_completed_layers_copy()
	if layers.is_empty():
		return false
	var game_state := get_tree().root.get_node_or_null("GameState") as GameStateService
	if game_state == null or not game_state.add_finished_burger(layers):
		return false
	_burger_stack.redo_burger()
	_clear_assembly_plate_state()
	return true


## 离开组装区前由 interact_zone 调用（与煎肉区 save_grill_state 同理）。
func save_assembly_state_to_game() -> void:
	_persist_assembly_plate()


## 进入场景时从 GameState 恢复案板半成品。
func _restore_assembly_plate() -> void:
	var game_state := _get_game_state()
	if game_state == null:
		return
	var layers := game_state.get_assembly_plate_layers()
	if layers.is_empty():
		return
	_burger_stack.restore_from_layers(layers)


## 将当前案板层写入 GameState（空则清除）。
func _persist_assembly_plate() -> void:
	var game_state := _get_game_state()
	if game_state == null:
		return
	if _burger_stack.is_empty():
		game_state.clear_assembly_plate()
	else:
		game_state.save_assembly_plate(_burger_stack.get_layers_copy())


## 清空 GameState 中的案板存档。
func _clear_assembly_plate_state() -> void:
	var game_state := _get_game_state()
	if game_state:
		game_state.clear_assembly_plate()


## 获取 autoload GameState 单例。
func _get_game_state() -> GameStateService:
	return get_tree().root.get_node_or_null("GameState") as GameStateService


## 显示短暂的操作失败提示。
func _show_cant_do() -> void:
	_cant_do_hint.text = CANT_DO_TEXT
	_cant_do_hint.visible = true
	_cant_do_timer = CANT_DO_DURATION


## 持久化案板后切回主场景。
func _exit_to_hub() -> void:
	_persist_assembly_plate()
	get_tree().change_scene_to_file(GameStateService.MAIN_SCENE)
