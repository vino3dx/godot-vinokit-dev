class_name VinoColor
extends RefCounted
## 颜色相关的静态工具函数，跟 vino_math.gd 配合用于 UI/Shader 参数调整场景。

## "#RRGGBB" 或 "#RRGGBBAA"（也接受不带 # 前缀）转 Color；非法输入返回 fallback。
static func from_hex(hex_string: String, fallback: Color = Color.WHITE) -> Color:
	var cleaned := hex_string.strip_edges().trim_prefix("#")
	if not cleaned.is_valid_html_color():
		VinoLogger.warn("VinoColor", "非法颜色字符串: %s" % hex_string)
		return fallback
	return Color.html(cleaned)

## Color 转 "#RRGGBB"（include_alpha=true 时为 "#RRGGBBAA"）。
static func to_hex(color: Color, include_alpha: bool = false) -> String:
	return "#" + color.to_html(include_alpha)

## 两个颜色之间按 t（0~1）插值，t 会被夹在 [0,1] 内，避免外插出现异常颜色。
static func lerp_clamped(from_color: Color, to_color: Color, t: float) -> Color:
	return from_color.lerp(to_color, clampf(t, 0.0, 1.0))

## 只改变透明度，返回新 Color，不修改原值（Color 是值类型，这里主要是语义化命名，避免手写 c.a = x）。
static func with_alpha(color: Color, alpha: float) -> Color:
	var result := color
	result.a = clampf(alpha, 0.0, 1.0)
	return result

## 根据背景色亮度自动选择黑或白文字颜色（YIQ 感知亮度公式），常用于动态生成的标签/徽章。
static func readable_text_color(background: Color) -> Color:
	var brightness := background.r * 299.0 + background.g * 587.0 + background.b * 114.0
	return Color.BLACK if brightness / 1000.0 > 0.5 else Color.WHITE
