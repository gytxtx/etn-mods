extends VBoxContainer

## Android 只生成外置客户端参数；配置操作不启动/关闭组网或游戏会话。
## 页面由官方联机菜单的 PageScroll 统一滚动与处理触屏拖动，这里不再自套 ScrollBox。
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
var _parameter_hint: Label
var _lan_hint: Label


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 8)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	_room_section()
	_parameter_section(cfg)
	_lan_section(cfg)


func _room_section() -> void:
	var card: Dictionary = UIStyle.card(self, "coop_et_room_code")
	var body: VBoxContainer = card.content
	UIStyle.note(body, "coop_et_external_intro")
	UIStyle.note(body, "coop_et_external_step_room")
	_room = UIStyle.line_edit(body)
	_room.max_length = 256
	_room.placeholder_text = "XXXX-XXXX-XXXX-XXXX"
	_room.tooltip_text = "coop_et_room_code_hint"
	_room.gui_input.connect(_on_field_gui_input.bind(_room))
	_controls.append(_room)
	_room.text_changed.connect(_refresh_network)


func _parameter_section(cfg: ConfigFile) -> void:
	var card: Dictionary = UIStyle.card(self, "coop_et_external_parameters")
	var body: VBoxContainer = card.content
	UIStyle.note(body, "coop_et_external_step_config")
	_network = _field(body, "coop_et_network_name", "coop_et_external_copy_name", _copy_network)
	_network.editable = false
	_secret = _field(body, "coop_et_network_secret", "coop_et_external_copy_secret", _copy_secret)
	_secret.editable = false
	_secret.secret = true
	_seed = _field(body, "coop_et_seed", "coop_et_external_copy_seed", _copy_seed)
	_seed.text = str(cfg.get_value("connection", "seed", ""))
	_seed.placeholder_text = "coop_et_seed_placeholder"
	_seed.tooltip_text = "coop_et_seed_hint"
	var row := UIStyle.row(body)
	_button(row, "coop_et_use_public_node", _use_public_node)
	_parameter_hint = _hint_label(body)


func _lan_section(cfg: ConfigFile) -> void:
	var card: Dictionary = UIStyle.card(self, "coop_et_lan_address")
	var body: VBoxContainer = card.content
	UIStyle.note(body, "coop_et_external_step_connect")
	UIStyle.note(body, "coop_et_external_step_lan")
	_host_ip = _field(body, "coop_et_host_ip")
	_host_ip.text = str(cfg.get_value("connection", "host_ip", "")).strip_edges()
	if _host_ip.text.is_empty():
		_host_ip.text = "10.144.144.1"
	_port = _field(body, "coop_et_port")
	_port.text = str(cfg.get_value("connection", "port", "24591"))
	var row := UIStyle.row(body)
	_button(row, "coop_et_external_copy_endpoint", _copy_endpoint)
	_lan_hint = _hint_label(body)
	UIStyle.note(body, "coop_et_external_lifecycle")
	_port.text_changed.connect(func(_text: String): _clear_hint(_lan_hint))
	_host_ip.text_changed.connect(func(_text: String): _clear_hint(_lan_hint))
	_port.focus_exited.connect(_save_settings)
	_host_ip.focus_exited.connect(_save_settings)


func get_interactive_controls() -> Array[Control]:
	return _controls


func _hint_label(parent: Container) -> Label:
	var label := UIStyle.note(parent, "")
	label.add_theme_color_override("font_color", UIStyle.ACCENT)
	label.visible = false
	return label


func _field(body: Container, key: String, copy_key: String = "", copy_action: Callable = Callable()) -> LineEdit:
	var row := UIStyle.row(body)
	UIStyle.row_label(row, key)
	var input := UIStyle.line_edit(row)
	input.gui_input.connect(_on_field_gui_input.bind(input))
	_controls.append(input)
	if not copy_key.is_empty():
		_button(row, copy_key, copy_action, false)
	return input


func _on_field_gui_input(event: InputEvent, input: LineEdit) -> void:
	# 本体关闭触屏模拟鼠标，沿用官方 LAN 输入框的显式聚焦与软键盘流程。
	if input.editable and event is InputEventScreenTouch and event.pressed:
		input.grab_focus()
		input.caret_column = input.text.length()
		DisplayServer.virtual_keyboard_show(input.text)
		input.accept_event()


func _button(row: Container, key: String, action: Callable, expand: bool = true) -> void:
	var button := Button.new()
	button.set_script(Action)
	button.text = key
	if expand:
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size.y = UIStyle.CONTROL_HEIGHT
	row.add_child(button)
	button.install_touch()
	button.pressed.connect(action)
	_controls.append(button)


func _refresh_network(_text: String) -> void:
	_clear_hints()
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
		_show_hint(_parameter_hint, "coop_et_code_invalid", true)
		return
	_copy(str(derived[key]), "coop_et_external_parameter_copied", _parameter_hint)


func _copy_seed() -> void:
	var value := _seed.text.strip_edges()
	if value.is_empty():
		_show_hint(_parameter_hint, "coop_et_external_seed_required", true)
		return
	_save_settings()
	_copy(value, "coop_et_external_parameter_copied", _parameter_hint)


func _use_public_node() -> void:
	_seed.text = PUBLIC_ENTRY
	_save_settings()
	_show_hint(_parameter_hint, "coop_et_public_node_filled")


func _copy_endpoint() -> void:
	var address := _host_ip.text.strip_edges()
	var port_text := _port.text.strip_edges()
	if not address.is_valid_ip_address() or address.contains(":") or not port_text.is_valid_int() \
		or port_text.to_int() < 1 or port_text.to_int() > 65535:
		_show_hint(_lan_hint, "coop_et_external_endpoint_invalid", true)
		return
	_save_settings()
	_copy("%s:%d" % [address, port_text.to_int()], "coop_et_external_endpoint_copied", _lan_hint)


func _copy(value: String, hint_key: String, hint: Label) -> void:
	if not DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		_show_hint(hint, "coop_et_external_clipboard_unavailable", true)
		return
	DisplayServer.clipboard_set(value)
	_show_hint(hint, hint_key)


func _show_hint(hint: Label, key: String, error: bool = false) -> void:
	# 同一时间只保留一条就近提示：参数卡片与 LAN 卡片不会同时留存旧消息。
	var other: Label = _lan_hint if hint == _parameter_hint else _parameter_hint
	_clear_hint(other)
	hint.text = key
	hint.visible = not key.is_empty()
	hint.add_theme_color_override("font_color", UIStyle.ERROR if error else UIStyle.ACCENT)


func _clear_hints() -> void:
	_clear_hint(_parameter_hint)
	_clear_hint(_lan_hint)


func _clear_hint(hint: Label) -> void:
	if hint == null or not is_instance_valid(hint):
		return
	hint.text = ""
	hint.visible = false


func _save_settings() -> void:
	# 与桌面共用设置，但保留其它字段；房间码、派生名称和密码仅保留在内存。
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("connection", "seed", _seed.text.strip_edges())
	cfg.set_value("connection", "host_ip", _host_ip.text.strip_edges())
	cfg.set_value("connection", "port", _port.text.strip_edges())
	cfg.save(SETTINGS_PATH)
