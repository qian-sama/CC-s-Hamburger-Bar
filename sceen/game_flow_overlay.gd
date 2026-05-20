## 开局 / 结算全屏提示：节点在场景中搭建；E 开始或重开，X 结束本局。
extends CanvasLayer

@onready var _backdrop: ColorRect = $Backdrop
@onready var _panel: PanelContainer = $Center/Panel
@onready var _title_label: Label = $Center/Panel/Margin/VBox/TitleLabel
@onready var _message_label: Label = $Center/Panel/Margin/VBox/MessageLabel
@onready var _hint_label: Label = $Center/Panel/Margin/VBox/HintLabel

var _game_state: GameStateService = null


func _ready() -> void:
	layer = 110
	_game_state = get_tree().root.get_node_or_null("GameState") as GameStateService
	if _game_state == null:
		return
	if not _game_state.session_changed.is_connected(_on_session_changed):
		_game_state.session_changed.connect(_on_session_changed)
	_apply_phase(_game_state.session_phase)


func _unhandled_input(event: InputEvent) -> void:
	if _game_state == null or not event.is_pressed() or event.is_echo():
		return
	var viewport := get_viewport()
	if event.is_action_pressed("Interact"):
		if _game_state.session_phase == GameStateService.SessionPhase.WAITING_START \
				or _game_state.session_phase == GameStateService.SessionPhase.GAME_OVER:
			_game_state.start_session()
			if viewport:
				viewport.set_input_as_handled()
		return
	if event.is_action_pressed("EndGame"):
		if _game_state.session_phase == GameStateService.SessionPhase.PLAYING:
			_game_state.end_session()
			if viewport:
				viewport.set_input_as_handled()


func _on_session_changed(phase: int) -> void:
	_apply_phase(phase)


func _apply_phase(phase: int) -> void:
	match phase:
		GameStateService.SessionPhase.PLAYING:
			visible = false
		GameStateService.SessionPhase.WAITING_START:
			visible = true
			_title_label.text = "CC's Hamburger Bar"
			_message_label.text = "欢迎来汉堡店打工"
			_hint_label.text = "按 E 开始游戏"
		GameStateService.SessionPhase.GAME_OVER:
			visible = true
			_title_label.text = "本局结束"
			if _game_state:
				_message_label.text = "本局收入\n$%.2f" % _game_state.last_session_earnings
			else:
				_message_label.text = "本局收入\n$0.00"
			_hint_label.text = "按 E 重新开始"
		_:
			visible = false
