## 组装区食材枚举与轮播贴图（帧顺序须与 IngredientCarousel 一致）。
extends RefCounted
class_name IngredientDefs

## 组装区可选食材类型
enum Type {
	PATTI,       ## 肉饼（熟度由 doneness 决定）
	PICKLE,      ## 酸黄瓜
	TOMATO,      ## 番茄
	ONION,       ## 洋葱
	LETTUCE,     ## 生菜
	CHEESE,      ## 芝士片
	BUN_BOTTOM,  ## 汉堡底
	BUN_TOP,     ## 汉堡顶
}

## 轮播中循环展示的蔬菜（不含肉饼与包）
const CAROUSEL_VEGGIES: Array[Type] = [
	Type.PICKLE,
	Type.TOMATO,
	Type.ONION,
	Type.LETTUCE,
	Type.CHEESE,
]

## 蔬菜叠层 / 轮播贴图
const TEXTURES: Dictionary = {
	Type.PICKLE: preload("res://游戏素材/食材/酸黄瓜.png"),
	Type.TOMATO: preload("res://游戏素材/食材/番茄.png"),
	Type.ONION: preload("res://游戏素材/食材/洋葱.png"),
	Type.LETTUCE: preload("res://游戏素材/食材/生菜.png"),
	Type.CHEESE: preload("res://游戏素材/食材/芝士片.png"),
}

## 肉饼按熟度对应的叠层贴图
const DONENESS_TEXTURES: Dictionary = {
	Patty.Doneness.THREE_MIN: preload("res://游戏素材/食材/3分熟肉饼.png"),
	Patty.Doneness.SEVEN_MIN: preload("res://游戏素材/食材/7分熟肉饼.png"),
	Patty.Doneness.WELL_DONE: preload("res://游戏素材/食材/全熟肉饼.png"),
	Patty.Doneness.BURNT: preload("res://游戏素材/食材/焦肉饼.png"),
}


## 熟肉盘有肉时才在轮播中加入肉饼帧。
static func build_carousel_order(include_patty: bool) -> Array[Type]:
	var order: Array[Type] = []
	if include_patty:
		order.append(Type.PATTI)
	for veggie in CAROUSEL_VEGGIES:
		order.append(veggie)
	return order


## 轮播当前帧贴图（肉饼帧用 peek_doneness 预览队首熟度）。
static func get_carousel_texture(type: Type, peek_doneness: int = -1) -> Texture2D:
	return get_stack_texture(type, peek_doneness)


## 订单 UI 显示的食材中文名。
static func get_display_name(type: Type, doneness: int = -1) -> String:
	match type:
		Type.BUN_TOP:
			return "汉堡顶"
		Type.BUN_BOTTOM:
			return "汉堡底"
		Type.PATTI:
			return "%s肉饼" % _patty_doneness_label(doneness)
		Type.PICKLE:
			return "酸黄瓜"
		Type.TOMATO:
			return "番茄"
		Type.ONION:
			return "洋葱"
		Type.LETTUCE:
			return "生菜"
		Type.CHEESE:
			return "芝士片"
		_:
			return "未知"


## 肉饼熟度中文简称（三分熟 / 七分熟等）。
static func _patty_doneness_label(doneness: int) -> String:
	match doneness:
		Patty.Doneness.THREE_MIN:
			return "三分熟"
		Patty.Doneness.SEVEN_MIN:
			return "七分熟"
		Patty.Doneness.WELL_DONE:
			return "全熟"
		Patty.Doneness.BURNT:
			return "焦"
		_:
			return ""


## 组装叠层 / 订单展示用的食材贴图；生肉或未指定熟度时肉饼返回 null。
static func get_stack_texture(type: Type, doneness: int = -1) -> Texture2D:
	match type:
		Type.BUN_BOTTOM:
			return preload("res://游戏素材/食材/汉堡下皮.png")
		Type.BUN_TOP:
			return preload("res://游戏素材/食材/汉堡上皮.png")
		Type.PATTI:
			if doneness < Patty.Doneness.THREE_MIN:
				return null
			return DONENESS_TEXTURES.get(
				doneness,
				DONENESS_TEXTURES[Patty.Doneness.THREE_MIN]
			) as Texture2D
		_:
			return TEXTURES.get(type) as Texture2D
