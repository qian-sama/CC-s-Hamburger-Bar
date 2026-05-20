## 全局订单看板：任意场景按 U 切换，左上角显示队首最多 4 单。
extends CanvasLayer

## 看板最多显示的小票数量
const MAX_VISIBLE := 4
const TICKET_CARD_SCENE := preload("res://sceen/order_ticket_card.tscn")

@onready var _tickets_row: HBoxContainer = $Root/Margin/VBox/Row
@onready var _hint: Label = $Root/Margin/VBox/Hint


func _ready() -> void:
	layer = 90
	visible = false
	var game_state := _game_state()
	if game_state and not game_state.order_tickets_changed.is_connected(_on_order_tickets_changed):
		game_state.order_tickets_changed.connect(_on_order_tickets_changed)


## 按 U（ViewOrders）切换看板显隐；打开时刷新内容。
func _unhandled_input(event: InputEvent) -> void:
	var game_state := _game_state()
	if game_state != null and not game_state.is_session_active():
		return
	if not event.is_action_pressed("ViewOrders"):
		return
	visible = not visible
	if visible:
		refresh()
	var viewport := get_viewport()
	if viewport:
		viewport.set_input_as_handled()


## 从 GameState 取队首订单并生成小票卡片。
func refresh() -> void:
	if _tickets_row == null:
		return
	for child in _tickets_row.get_children():
		child.queue_free()
	var game_state := _game_state()
	if game_state == null:
		_set_hint(true, "暂无订单")
		return
	var tickets: Array = game_state.get_order_tickets_head(MAX_VISIBLE)
	if tickets.is_empty():
		_set_hint(true, "暂无订单")
		return
	_set_hint(false, "")
	for ticket in tickets:
		if ticket is Dictionary:
			var card := TICKET_CARD_SCENE.instantiate() as OrderTicketCard
			_tickets_row.add_child(card)
			card.set_layers(ticket.get("layers", []))


## 控制「暂无订单」提示文案显隐。
func _set_hint(show: bool, text: String) -> void:
	_hint.visible = show
	_hint.text = text


## 订单队列变化且看板打开时自动刷新。
func _on_order_tickets_changed() -> void:
	if visible:
		refresh()


## 获取 autoload GameState 单例。
func _game_state() -> GameStateService:
	return get_tree().root.get_node_or_null("GameState") as GameStateService
