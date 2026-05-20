## 通用交互区域：玩家进入后显示 Press E，按 E 切换到指定场景。
## 挂在主场景的 GrillZone / AssemblyZone / CashierZone（进分区）或分区场景的 ExitZone（回主场景）上。
extends Area2D

## 按 E 后要加载的场景路径；在检查器里为每个 Area 单独设置。
@export_file("*.tscn") var target_scene: String = ""


func _ready() -> void:
	# 若玩家出生时已在区域内，body_entered 不会触发，需主动检测一次重叠物体
	await get_tree().physics_frame
	for body in get_overlapping_bodies():
		_on_body_entered(body)


## 有物体进入区域（需将 Area2D 的 body_entered 信号连到此方法）。
func _on_body_entered(body: Node2D) -> void:
	if body.has_method("enter_interact_zone"):
		body.enter_interact_zone(self)


## 物体离开区域（需将 body_exited 信号连到此方法）。
func _on_body_exited(body: Node2D) -> void:
	if body.has_method("exit_interact_zone"):
		body.exit_interact_zone(self)


## 获取 autoload GameState 单例。
func _get_game_state() -> GameStateService:
	return get_tree().root.get_node_or_null("GameState") as GameStateService


## 执行场景切换（由玩家的 _unhandled_input 在按 E 时调用）。
func interact(player: Node2D = null) -> void:
	var game_state := _get_game_state()
	if game_state != null and not game_state.is_session_active():
		return
	if target_scene.is_empty():
		return
	_persist_grill_state_before_leave()
	_persist_assembly_state_before_leave()
	if player and game_state and target_scene in [
		GameStateService.GRILL_SCENE,
		GameStateService.ASSEMBLE_SCENE,
		GameStateService.CASHIER_SCENE,
	]:
		game_state.save_hub_return(player.global_position)
	get_tree().change_scene_to_file(target_scene)


## 离开煎肉区前写入铁板状态（_exit_tree 时子节点已先释放，须提前保存）
func _persist_grill_state_before_leave() -> void:
	var current := get_tree().current_scene
	if current == null or current.scene_file_path != GameStateService.GRILL_SCENE:
		return
	var work_areas := current.get_node_or_null("WorkAreas")
	if work_areas and work_areas.has_method("save_grill_state_to_game"):
		work_areas.save_grill_state_to_game()


func _persist_assembly_state_before_leave() -> void:
	var current := get_tree().current_scene
	if current == null or current.scene_file_path != GameStateService.ASSEMBLE_SCENE:
		return
	if current.has_method("save_assembly_state_to_game"):
		current.save_assembly_state_to_game()
