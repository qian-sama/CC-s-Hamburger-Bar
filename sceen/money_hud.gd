## 右上角收入 HUD：节点在场景中搭建，脚本只刷新金额 Label。
extends CanvasLayer

const LAST_PAYMENT_SHOW_SEC := 2.5

@onready var _amount_label: Label = $Root/Margin/VBox/AmountRow/AmountLabel
@onready var _last_payment_label: Label = $Root/Margin/VBox/LastPaymentLabel

var _last_payment_timer: float = 0.0


func _ready() -> void:
	layer = 100
	var game_state := _game_state()
	if game_state == null:
		return
	if not game_state.money_changed.is_connected(_on_money_changed):
		game_state.money_changed.connect(_on_money_changed)
	if not game_state.session_changed.is_connected(_on_session_changed):
		game_state.session_changed.connect(_on_session_changed)
	_sync_total(game_state.player_money)
	_last_payment_label.visible = false
	_on_session_changed(game_state.session_phase)


func _process(delta: float) -> void:
	if _last_payment_timer <= 0.0:
		return
	_last_payment_timer -= delta
	if _last_payment_timer <= 0.0:
		_last_payment_label.visible = false


func _on_session_changed(phase: int) -> void:
	visible = phase == GameStateService.SessionPhase.PLAYING


func _on_money_changed(total: float, delta: float, perfect_match: bool) -> void:
	_sync_total(total)
	_show_last_payment(delta, perfect_match)


func _sync_total(total: float) -> void:
	if _amount_label:
		_amount_label.text = "$%.2f" % total


func _show_last_payment(delta: float, perfect_match: bool) -> void:
	if _last_payment_label == null or delta <= 0.0:
		return
	var tag := "✓" if perfect_match else "△"
	_last_payment_label.text = "%s +$%.2f" % [tag, delta]
	_last_payment_label.visible = true
	_last_payment_timer = LAST_PAYMENT_SHOW_SEC


func _game_state() -> GameStateService:
	return get_tree().root.get_node_or_null("GameState") as GameStateService
