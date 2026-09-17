class_name VinoString
extends RefCounted
## 字符串相关的静态工具函数。网络模块（UDPSender/UDPReceiver）里手写过的 hex 转换
## 已经出现两次，这里统一收口，避免以后每个模块各写一份。

## PackedByteArray 转十六进制字符串，例如 [0xAB, 0x01] -> "ab01"。
static func bytes_to_hex(bytes: PackedByteArray) -> String:
	return bytes.hex_encode()

## 十六进制字符串转 PackedByteArray；输入非法（奇数长度/非法字符）时返回空数组并打印警告。
static func hex_to_bytes(hex_string: String) -> PackedByteArray:
	var cleaned := hex_string.strip_edges().replace(" ", "")
	if cleaned.length() % 2 != 0:
		VinoLogger.warn("VinoString", "hex_to_bytes: 长度为奇数，无法解析 -> %s" % hex_string)
		return PackedByteArray()
	var result := PackedByteArray()
	for i in range(0, cleaned.length(), 2):
		var byte_str := cleaned.substr(i, 2)
		if not byte_str.is_valid_hex_number():
			VinoLogger.warn("VinoString", "hex_to_bytes: 非法字符 -> %s" % byte_str)
			return PackedByteArray()
		result.append(byte_str.hex_to_int())
	return result

## 判断字符串是否为空或全是空白字符（比 String.is_empty() 更实用，能过滤掉 "   " 这种情况）。
static func is_blank(text: String) -> bool:
	return text.strip_edges().is_empty()

## 超出 max_length 时截断并加省略号，UI 里显示长文件名/长标题时常用。
static func truncate(text: String, max_length: int, ellipsis: String = "...") -> String:
	if text.length() <= max_length:
		return text
	var keep := max_length - ellipsis.length()
	if keep <= 0:
		return ellipsis
	return text.substr(0, keep) + ellipsis

## snake_case 转 PascalCase，例如 "vino_math" -> "VinoMath"。做动态类名拼接、日志分类时能用到。
static func snake_to_pascal(text: String) -> String:
	var parts := text.split("_")
	var result := ""
	for part in parts:
		if part.is_empty():
			continue
		result += part[0].to_upper() + part.substr(1)
	return result

## 安全格式化字节大小为可读字符串，例如 1536 -> "1.5 KB"。
static func format_bytes(size: int) -> String:
	var units := ["B", "KB", "MB", "GB", "TB"]
	var value := float(size)
	var unit_index := 0
	while value >= 1024.0 and unit_index < units.size() - 1:
		value /= 1024.0
		unit_index += 1
	if unit_index == 0:
		return "%d %s" % [int(value), units[unit_index]]
	return "%.1f %s" % [value, units[unit_index]]
