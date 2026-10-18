extends RefCounted

## 房间码：16 位 34 进制（去掉易混的 I/O），末位是对 7 取模的校验位。
## 网络名与密码由房间码经 SHA-256 派生 —— 码即凭据，不需要房间服务器，也不落盘、不进日志。
## 与 Scaffolding/Terracotta 的码化思路一致（纯本地派生），但用自己的前缀与哈希，避免与其它项目串网。

const CHARSET: String = "0123456789ABCDEFGHJKLMNPQRSTUVWXYZ"
const CODE_LEN: int = 16
const NAME_PREFIX: String = "etn-coop-"
const DOMAIN: String = "etn-coop-room"
const MODULUS: int = 7


static func generate() -> String:
	# 前 15 位随机（34^15 ≈ 76 bit），第 16 位解出使整码对 7 取模为 0。
	var body: String = ""
	var bytes: PackedByteArray = Crypto.new().generate_random_bytes((CODE_LEN - 1) * 2)
	for index in CODE_LEN - 1:
		var sample: int = bytes[index * 2] * 256 + bytes[index * 2 + 1]
		body += CHARSET[sample % CHARSET.length()]
	return body + CHARSET[_checksum_digit(body)]


static func normalize(text: String) -> String:
	# 接受大小写、空格、分组连字符与 Scaffolding 风格前缀；I/O 按易混规则映射。
	var cleaned: String = ""
	for character in text.strip_edges().to_upper():
		var mapped: String = character
		if mapped == "I":
			mapped = "1"
		elif mapped == "O":
			mapped = "0"
		if CHARSET.contains(mapped):
			cleaned += mapped
	return cleaned


static func is_valid(code: String) -> bool:
	if code.length() != CODE_LEN:
		return false
	var value: int = 0
	for character in code:
		var index: int = CHARSET.find(character)
		if index < 0:
			return false
		value = (value * CHARSET.length() + index) % MODULUS
	return value == 0


static func format(code: String) -> String:
	# XXXX-XXXX-XXXX-XXXX，便于朗读与核对。
	var out: String = ""
	var index: int = 0
	while index < code.length():
		if index > 0:
			out += "-"
		out += code.substr(index, 4)
		index += 4
	return out


static func derive(code: String) -> Dictionary:
	var normalized: String = normalize(code)
	if not is_valid(normalized):
		return {}
	return {
		"network_name": NAME_PREFIX + _digest("name", normalized).substr(0, 12),
		"network_secret": _digest("secret", normalized),
	}


static func parse(text: String) -> Dictionary:
	# 支持「房间码」与「房间码@入口地址」两种粘贴形式（入口留空时用内置默认入口）。
	var parts: PackedStringArray = text.strip_edges().split("@", false)
	var code: String = normalize(parts[0]) if parts.size() > 0 else ""
	return {
		"code": code,
		"seed": parts[1].strip_edges() if parts.size() > 1 else "",
		"valid": is_valid(code),
	}


static func _checksum_digit(body: String) -> int:
	# 整码满足 (body * 34 + digit) ≡ 0 (mod 7)；34 ≡ 6 (mod 7)，故 digit ≡ -body * 6。
	var value: int = 0
	for character in body:
		value = (value * CHARSET.length() + CHARSET.find(character)) % MODULUS
	return (MODULUS - (value * (CHARSET.length() % MODULUS)) % MODULUS) % MODULUS


static func _digest(tag: String, code: String) -> String:
	return ("%s:%s:%s" % [DOMAIN, tag, code]).sha256_text()
