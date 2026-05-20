## 交餐评分：订单与成品层对比，计算 $5~$10 基础价及错漏扣款。
extends RefCounted
class_name OrderScoring

const MIN_PRICE := 5.0
const MAX_PRICE := 10.0
const PENALTY_PER_ERROR := 0.5
const MIN_PAY_RATIO := 0.6
const MIN_FILL_LAYERS := 1
const MAX_FILL_LAYERS := OrderGenerator.MAX_FILL_LAYERS


## 返回 { amount, base_price, error_count, perfect_match }
static func calculate_payment(order_layers: Array, delivered_layers: Array) -> Dictionary:
	var base_price := base_price_for_order(order_layers)
	var error_count := count_mismatch_errors(order_layers, delivered_layers)
	var perfect_match := error_count == 0
	var amount := base_price
	if not perfect_match:
		amount = maxf(base_price * MIN_PAY_RATIO, base_price - float(error_count) * PENALTY_PER_ERROR)
	return {
		"amount": round_money(amount),
		"base_price": round_money(base_price),
		"error_count": error_count,
		"perfect_match": perfect_match,
	}


## 按订单馅料层数线性定价（$5~$10）；上下包不计入。
static func base_price_for_order(order_layers: Array) -> float:
	var fill_count := _fill_layer_count(order_layers)
	fill_count = clampi(fill_count, MIN_FILL_LAYERS, MAX_FILL_LAYERS)
	if MAX_FILL_LAYERS <= MIN_FILL_LAYERS:
		return MIN_PRICE
	var t := float(fill_count - MIN_FILL_LAYERS) / float(MAX_FILL_LAYERS - MIN_FILL_LAYERS)
	return lerpf(MIN_PRICE, MAX_PRICE, t)


## 缺少或多余的食材层总数（肉饼需熟度一致，其它只看 type）。
static func count_mismatch_errors(order_layers: Array, delivered_layers: Array) -> int:
	var order_counts := _layer_counts(order_layers)
	var delivered_counts := _layer_counts(delivered_layers)
	var errors := 0
	var keys: Dictionary = {}
	for key in order_counts:
		keys[key] = true
	for key in delivered_counts:
		keys[key] = true
	for key in keys:
		errors += absi(order_counts.get(key, 0) - delivered_counts.get(key, 0))
	return errors


static func round_money(value: float) -> float:
	return snappedf(value, 0.01)


static func _fill_layer_count(layers: Array) -> int:
	var normalized := OrderGenerator.normalize_layers_for_display(layers)
	if normalized.size() <= 2:
		return 0
	return normalized.size() - 2


static func _layer_counts(layers: Array) -> Dictionary:
	var counts: Dictionary = {}
	var normalized := OrderGenerator.normalize_layers_for_display(layers)
	for layer in normalized:
		if not layer is Dictionary:
			continue
		var key := _layer_key(layer)
		counts[key] = counts.get(key, 0) + 1
	return counts


static func _layer_key(layer: Dictionary) -> String:
	var type: int = layer.get("type", -1)
	var doneness: int = layer.get("doneness", -1)
	if type == IngredientDefs.Type.PATTI:
		return "%d:%d" % [type, doneness]
	return str(type)
