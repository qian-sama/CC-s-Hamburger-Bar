## 随机生成顾客订单层（下包→馅料→顶包，馅料 1~8 层且至少含一块肉饼）。
extends RefCounted
class_name OrderGenerator

## 随机馅料层数上限（不含上下包）
const MAX_FILL_LAYERS := 8

## 可随机出现的蔬菜类型
const _VEGGIE_TYPES: Array[IngredientDefs.Type] = [
	IngredientDefs.Type.PICKLE,
	IngredientDefs.Type.TOMATO,
	IngredientDefs.Type.ONION,
	IngredientDefs.Type.LETTUCE,
	IngredientDefs.Type.CHEESE,
]

## 点单肉饼熟度权重：七分熟 40%、全熟 40%、三分熟 20%（不含焦 / 生）
const _PATTY_DONENESS_SEVEN_CHANCE := 0.4
const _PATTY_DONENESS_WELL_CHANCE := 0.4


## 生成一份完整订单：底包 + 打乱顺序的馅料（必含一块肉饼）+ 顶包。
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


## 点单展示：下包 → 馅料 → 顶包；若无顶包则补上。
static func normalize_layers_for_display(layers: Array) -> Array:
	var bottom: Dictionary = {"type": IngredientDefs.Type.BUN_BOTTOM, "doneness": -1}
	var top: Dictionary = {"type": IngredientDefs.Type.BUN_TOP, "doneness": -1}
	var fills: Array = []
	for layer in layers:
		if not layer is Dictionary:
			continue
		var t: int = layer.get("type", -1)
		match t:
			IngredientDefs.Type.BUN_BOTTOM:
				bottom = layer.duplicate()
			IngredientDefs.Type.BUN_TOP:
				top = layer.duplicate()
			_:
				fills.append(layer.duplicate())
	var result: Array = [bottom]
	result.append_array(fills)
	result.append(top)
	return result


## 订单 UI：顶包在上、底包在下。
static func layers_top_first(layers: Array) -> Array:
	var ordered: Array = []
	for layer in layers:
		if layer is Dictionary:
			ordered.append(layer.duplicate())
	ordered.reverse()
	return ordered


## 生成一条带加权随机熟度的肉饼层字典。
static func _make_patty_layer() -> Dictionary:
	return {
		"type": IngredientDefs.Type.PATTI,
		"doneness": _roll_order_patty_doneness(),
	}


## 按权重抽取订单肉饼熟度。
static func _roll_order_patty_doneness() -> int:
	var roll := randf()
	if roll < _PATTY_DONENESS_SEVEN_CHANCE:
		return Patty.Doneness.SEVEN_MIN
	if roll < _PATTY_DONENESS_SEVEN_CHANCE + _PATTY_DONENESS_WELL_CHANCE:
		return Patty.Doneness.WELL_DONE
	return Patty.Doneness.THREE_MIN
