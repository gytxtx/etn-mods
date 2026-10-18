extends VBoxContainer

## Android 只生成外置客户端参数；配置操作不启动/关闭组网或游戏会话。
var controller: Node
const RoomCode := preload("res://mods/etn_coop_easytier/net/room_code.gd")
const Action := preload("res://mods/etn_coop_easytier/ui/action_button.gd")
const UIStyle := preload("res://mods/etn_coop_easytier/ui/ui_style.gd")
const SETTINGS_PATH := "user://etn_coop_easytier.cfg"
const PUBLIC_ENTRY := "udp://et.saibamidori.com:11010"
var _controls: Array[Control] = []
var _room: LineEdit
var _network: LineEdit
var _secret: LineEdit
var _seed: LineEdit
var _host_ip: LineEdit
var _port: LineEdit
var _hint: Label


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 6)
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	_note("coop_et_external_intro")
	_note("coop_et_external_step_room")
	_room = _field("coop_et_room_code")
	_room.max_length = 256
	_room.placeholder_text = "XXXX-XXXX-XXXX-XXXX"
	_room.tooltip_text = "coop_et_room_code_hint"
	_note("coop_et_external_step_config")
	_network = _field("coop_et_network_name", "coop_et_external_copy_name", _copy_network)
	_network.editable = false
	_secret = _field("coop_et_network_secret", "coop_et_external_copy_secret", _copy_secret)
	_secret.editable = false
	_secret.secret = true
	_seed = _field("coop_et_seed", "coop_et_external_copy_seed", _copy_seed)
	_seed.text = str(cfg.get_value("connection", "seed", ""))
	_seed.placeholder_text = "coop_et_seed_placeholder"
	_seed.tooltip_text = "coop_et_seed_hint"
	var node_row := HBoxContainer.new()
	add_child(node_row)
	_button(node_row, "coop_et_use_public_node", _use_public_node)
	_note("coop_et_external_step_connect")
	_note("coop_et_external_step_lan")
	_host_ip = _field("coop_et_host_ip")
	_host_ip.text = str(cfg.get_value("connection", "host_ip", "")).strip_edges()
	if _host_ip.text.is_empty():
		_host_ip.text = "10.144.144.1"
	_port = _field("coop_et_port")
	_port.text = str(cfg.get_value("connection", "port", "24591"))
	var join_row := HBoxContainer.new()
	add_child(join_row)
	_button(join_row, "coop_et_external_copy_endpoint", _copy_endpoint)
	_note("coop_et_external_lifecycle")
	_hint = _note("")
	_hint.add_theme_color_override("font_color", UIStyle.ACCENT)
	_hint.visible = false
	_room.text_changed.connect(_refresh_network)
	for field in [_seed, _host_ip, _port]:
		field.text_changed.connect(func(_text: String): _set_hint(""))
		field.focus_exited.connect(_save_settings)


func get_interactive_controls() -> Array[Control]:
	return _controls


func _note(key: String) -> Label:
	var label := Label.new()
	label.text = key
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", UIStyle.MUTED)
	add_child(label)
	return label


func _field(key: String, copy_key: String = "", copy_action: Callable = Callable()) -> LineEdit:
	_note(key)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	add_child(row)
	var input := LineEdit.new()
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.custom_minimum_size = Vector2(0, 28)
	input.mouse_filter = Control.MOUSE_FILTER_PASS
	input.gui_input.connect(_on_field_gui_input.bind(input))
	row.add_child(input)
	_controls.append(input)
	if not copy_key.is_empty():
		_button(row, copy_key, copy_action)
	return input


func _on_field_gui_input(event: InputEvent, input: LineEdit) -> void:
	# 本体关闭触屏模拟鼠标，沿用官方 LAN 输入框的显式聚焦与软键盘流程。
	if input.editable and event is InputEventScreenTouch and event.pressed:
		input.grab_focus()
		input.caret_column = input.text.length()
		DisplayServer.virtual_keyboard_show(input.text)
		input.accept_event()


func _button(row: HBoxContainer, key: String, action: Callable) -> void:
	var button := Button.new()
	button.set_script(Action)
	button.text = key
	button.custom_minimum_size.y = 28
	button.add_theme_font_size_override("font_size", 10)
	row.add_child(button)
	button.install_touch()
	button.pressed.connect(action)
	_controls.append(button)


func _refresh_network(_text: String) -> void:
	_set_hint("")
	var parsed: Dictionary = RoomCode.parse(_room.text)
	var derived: Dictionary = RoomCode.derive(str(parsed.code))
	_network.text = str(derived.get("network_name", ""))
	_secret.text = str(derived.get("network_secret", ""))
	# 与桌面一致支持「房间码@入口」；只在合法码变更时回填，之后允许玩家编辑。
	if not derived.is_empty() and not str(parsed.seed).is_empty():
		_seed.text = str(parsed.seed)


func _copy_network() -> void:
	_copy_credential("network_name")


func _copy_secret() -> void:
	_copy_credential("network_secret")


func _copy_credential(key: String) -> void:
	# 每次复制重新校验当前房间码，避免复制输入修改前的旧凭据。
	var parsed: Dictionary = RoomCode.parse(_room.text)
	var derived: Dictionary = RoomCode.derive(str(parsed.code))
	if derived.is_empty():
		_set_hint("coop_et_code_invalid")
		return
	_copy(str(derived[key]), "coop_et_external_parameter_copied")


func _copy_seed() -> void:
	var value := _seed.text.strip_edges()
	if value.is_empty():
		_set_hint("coop_et_external_seed_required")
		return
	_save_settings()
	_copy(value, "coop_et_external_parameter_copied")


func _use_public_node() -> void:
	_seed.text = PUBLIC_ENTRY
	_save_settings()
	_set_hint("coop_et_public_node_filled")


func _copy_endpoint() -> void:
	var address := _host_ip.text.strip_edges()
	var port_text := _port.text.strip_edges()
	if not address.is_valid_ip_address() or address.contains(":") or not port_text.is_valid_int() \
		or port_text.to_int() < 1 or port_text.to_int() > 65535:
		_set_hint("coop_et_external_endpoint_invalid")
		return
	_save_settings()
	_copy("%s:%d" % [address, port_text.to_int()], "coop_et_external_endpoint_copied")


func _copy(value: String, hint_key: String) -> void:
	if not DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		_set_hint("coop_et_external_clipboard_unavailable")
		return
	DisplayServer.clipboard_set(value)
	_set_hint(hint_key)


func _set_hint(key: String) -> void:
	_hint.text = key
	_hint.visible = not key.is_empty()


func _save_settings() -> void:
	# 与桌面共用设置，但保留其它字段；房间码、派生名称和密码仅保留在内存。
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("connection", "seed", _seed.text.strip_edges())
	cfg.set_value("connection", "host_ip", _host_ip.text.strip_edges())
	cfg.set_value("connection", "port", _port.text.strip_edges())
	cfg.save(SETTINGS_PATH)
