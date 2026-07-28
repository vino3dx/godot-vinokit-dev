extends Node
## === 离线授权许可管理 ===
## 功能：
##  - AES-256-CBC 解密 license.dat
##  - 校验签发时间(issue)与到期时间(expire)，防止回拨系统时间绕过授权
##  - 支持编辑器与导出环境
##  - 授权失效或日期异常自动退出
## 授权 JSON 示例：
## { "issue": "2026-07-24", "expire": "2027-12-30" }
## ====================================

const LICENSE_CONFIG_PATH := "res://addons/license_manager/license_config.cfg"
const TIME_RECORD_PATH := "user://sys_time.dat" ## 本地持久化记录最后运行时间 (C:\Users\<你的Windows用户名>\AppData\Roaming\Godot\app_userdata\<项目名称>\sys_time.dat)

var KEY: PackedByteArray
var IV: PackedByteArray

func _ready():
	if not _is_module_enabled():
		print("【LSM】模块已禁用（license_config.cfg），跳过。")
		return
		
	KEY = "1234567890ABCDEF1234567890ABCDEF".to_utf8_buffer()
	IV  = "ABCDEF1234567890".to_utf8_buffer()
	
	# 启动时自动检查，过期/回拨/异常则静默退出
	if not check_license():
		await get_tree().process_frame
		get_tree().quit()


# =========================
# 获取 license 路径
# =========================
func get_license_path() -> String:
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("res://") + "license.dat"
	return OS.get_executable_path().get_base_dir() + "/license.dat"


# =========================
# 读取模块自身开关(不依赖 ProjectSettings)
# =========================
func _is_module_enabled() -> bool:
	var config := ConfigFile.new()
	var err := config.load(LICENSE_CONFIG_PATH)

	if err != OK:
		config.set_value("license", "enabled", false)
		config.save(LICENSE_CONFIG_PATH)
		return false

	return config.get_value("license", "enabled", false)


# =========================
# 读取文件
# =========================
func read_file(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var txt = f.get_as_text()
	f.close()
	return txt.strip_edges().replace("\n", "").replace("\r", "").replace(" ", "")


# =========================
# AES-256-CBC 解密
# =========================
func decrypt(base64_text: String) -> String:
	var encrypted: PackedByteArray = Marshalls.base64_to_raw(base64_text)
	if encrypted.size() == 0:
		return ""
	
	var aes := AESContext.new()
	aes.start(AESContext.MODE_CBC_DECRYPT, KEY, IV)
	var decrypted: PackedByteArray = aes.update(encrypted)
	aes.finish()
	
	if decrypted.size() == 0:
		return ""
	
	var pad_len = decrypted[decrypted.size() - 1]
	if pad_len >= 1 and pad_len <= 16:
		for i in range(pad_len):
			if decrypted[decrypted.size() - 1 - i] != pad_len:
				return ""
		decrypted = decrypted.slice(0, decrypted.size() - pad_len)
	
	return decrypted.get_string_from_utf8()


# =========================
# JSON 解析
# =========================
func parse_json(text: String) -> Dictionary:
	var result = JSON.parse_string(text)
	if result == null or not result is Dictionary:
		return {}
	return result


# =========================
# 判断闰年
# =========================
func is_leap_year(year:int) -> bool:
	return (year % 4 == 0 and year % 100 != 0) or (year % 400 == 0)


# =========================
# 日期合法性检查
# =========================
func is_valid_date(date_str:String) -> bool:

	if date_str.length() != 10:
		return false

	var parts = date_str.split("-")

	if parts.size() != 3:
		return false

	var year = parts[0].to_int()
	var month = parts[1].to_int()
	var day = parts[2].to_int()

	if year < 2000 or year > 9999:
		return false

	if month < 1 or month > 12:
		return false

	var max_day = 31

	match month:
		4, 6, 9, 11:
			max_day = 30
		2:
			max_day = 28
			if is_leap_year(year):
				max_day = 29

	if day < 1 or day > max_day:
		return false

	return true


# =========================
# 将 YYYY-MM-DD 转为 unix 秒数（用于比较）
# =========================
func _to_unix(date_str: String) -> int:
	return Time.get_unix_time_from_datetime_string(date_str + "T00:00:00")


# 计算到期留存天数（返回：>=0 为剩余天数，-1 为已过期，-2 为日期异常）
func _get_days_left(expire: String) -> int:
	if not is_valid_date(expire):
		return -2

	var today = Time.get_date_string_from_system(true)
	if not is_valid_date(today):
		return -2

	var t_stamp = _to_unix(today)
	var e_stamp = _to_unix(expire)

	if t_stamp > e_stamp:
		return -1

	return int((e_stamp - t_stamp) / 86400)


# =========================
# 进阶防回拨：检查并更新本地最后运行时间
# =========================
func _check_and_update_last_time(today_str: String) -> bool:
	var current_stamp = _to_unix(today_str)
	
	# 1. 如果存在历史记录文件，进行时间线对比
	if FileAccess.file_exists(TIME_RECORD_PATH):
		var file = FileAccess.open(TIME_RECORD_PATH, FileAccess.READ)
		if file:
			var saved_stamp = file.get_64()
			file.close()
			
			# 核心拦截：如果当前系统时间小于本地记录的时间，说明系统时间被篡改（往回拨了）
			if current_stamp < saved_stamp:
				print("[LSM] 致命错误: 检测到系统时间被篡改（当前时间早于历史运行记录）！")
				return false
				
	# 2. 校验通过，刷新本地的“最高运行时间”记录
	var file = FileAccess.open(TIME_RECORD_PATH, FileAccess.WRITE)
	if file:
		file.store_64(current_stamp)
		file.close()
		
	return true


# =========================
# 检查授权主入口 (已整合最高时间记录校验)
# =========================
func check_license() -> bool:
	var path = get_license_path()
	if not FileAccess.file_exists(path):
		print("[LSM] 错误: 找不到 license.dat 文件")
		return false
	
	var raw = read_file(path)
	if raw.is_empty():
		print("[LSM] 错误: license.dat 内容为空")
		return false
	
	var decrypted = decrypt(raw)
	if decrypted.is_empty():
		print("[LSM] 错误: 解密失败，密文损坏或密钥不匹配")
		return false
	
	var data = parse_json(decrypted)
	if data.is_empty() or not data.has("expire") or not data.has("issue"):
		print("[LSM] 错误: 授权数据 JSON 格式无效")
		return false
	
	var issue_date: String = data["issue"]
	var expire_date: String = data["expire"]
	
	if not is_valid_date(issue_date) or not is_valid_date(expire_date):
		print("[LSM] 错误: 授权文件中的日期格式不合法")
		return false
	
	var today = Time.get_date_string_from_system(true)
	
	# 1. 校验授权文件内部逻辑 (签发时间不得晚于到期时间)
	if _to_unix(issue_date) > _to_unix(expire_date):
		print("[LSM] 错误: 授权文件逻辑异常 (签发时间晚于到期时间)")
		return false
	
	# 2. 基础防回拨：系统时间绝对不能早于签发日
	if _to_unix(today) < _to_unix(issue_date):
		print("[LSM] 警告: 检测到系统时钟回拨！签发日: %s, 系统日: %s" % [issue_date, today])
		return false
		
	# 3. 进阶防回拨：系统时间绝对不能早于上一次成功运行的时间
	if not _check_and_update_last_time(today):
		return false
	
	# 4. 最终判定剩余天数
	var days_left = _get_days_left(expire_date)
	if days_left >= 0:
		print("[LSM] 验证通过 | 到期日: %s | 剩余天数: %d 天" % [expire_date, days_left])
		return true
	else:
		print("[LSM] 验证失败: 授权已过期")
		return false
