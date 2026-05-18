## 通用交互区域：玩家进入后显示 Press E，按 E 切换到指定场景。
## 挂在主场景的 GrillZone / AssemblyZone（进分区）或分区场景的 ExitZone（回主场景）上。
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


func _get_game_state() -> GameStateService:
	return get_tree().root.get_node_or_null("GameState") as GameStateService


## 执行场景切换（由玩家的 _unhandled_input 在按 E 时调用）。
func interact(player: Node2D = null) -> void:
	if target_scene.is_empty():
		return
	if player and target_scene in [GameStateService.GRILL_SCENE, GameStateService.ASSEMBLE_SCENE]:
		var game_state := _get_game_state()
		if game_state:
			game_state.save_hub_return(player.global_position)
	get_tree().change_scene_to_file(target_scene)
