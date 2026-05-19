## 随机生成顾客订单层（下包→馅料→顶包，馅料 1~8 层且至少含一块肉饼）。
extends RefCounted
class_name OrderGenerator

const MAX_FILL_LAYERS := 8

const _VEGGIE_TYPES: Array[IngredientDefs.Type] = [
	IngredientDefs.Type.PICKLE,
	IngredientDefs.Type.TOMATO,
	IngredientDefs.Type.ONION,
	IngredientDefs.Type.LETTUCE,
	IngredientDefs.Type.CHEESE,
]

const _ORDER_DONENESS: Array[int] = [
	Patty.Doneness.THREE_MIN,
	Patty.Doneness.SEVEN_MIN,
	Patty.Doneness.WELL_DONE,
]


static func generate_order_layers() -> Array:
	var fill_count := randi_range(1, MAX_FILL_LAYERS)
	var fills: Array = []
	fills.append(_make_patty_layer())
	for _i in range(fill_count - 1):
		var veggie: IngredientDefs.Type = _VEGGIE_TYPES.pick_random()
		fills.append({"type": veggie, "doneness": -1})
	fills.shuffle()
	var layers: Array = [
		{"type": IngredientDefs.Type.BUN_BOTTOM, "doneness": -1},
	]
	layers.append_array(fills)
	layers.append({"type": IngredientDefs.Type.BUN_TOP, "doneness": -1})
	return layers


## 订单 UI：顶包在上、底包在下。
static func layers_top_first(layers: Array) -> Array:
	var ordered: Array = []
	for layer in layers:
		if layer is Dictionary:
			ordered.append(layer.duplicate())
	ordered.reverse()
	return ordered


static func _make_patty_layer() -> Dictionary:
	return {
		"type": IngredientDefs.Type.PATTI,
		"doneness": _ORDER_DONENESS.pick_random(),
	}
