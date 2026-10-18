extends Node

## 不覆盖官方资源、不接管本体钩子、不复制官方 CoopNet。
const Backend := preload("res://mods/etn_coop_easytier/net/easytier_backend.gd")
const Page := preload("res://mods/etn_coop_easytier/ui/easytier_page.gd")
const ExternalPage := preload("res://mods/etn_coop_easytier/ui/easytier_external_page.gd")
const I18n := preload("res://mods/etn_coop_easytier/i18n/easytier_i18n.gd")
const RoomCode := preload("res://mods/etn_coop_easytier/net/room_code.gd")
const ID := "etn_coop_easytier"
signal prepared(endpoint: Dictionary)
signal failed(message: String)
var menu_title := "EasyTier"
var _api: Node
var _backend: Node
var _room_code := ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_api = get_tree().get_first_node_in_group("CoopExtensionHost")
	if _api == null or not _api.has_method("get_api_version") or _api.get_api_version() != 1 or not _api.has_method("get_menu_pages"):
		push_warning("[etn_coop_easytier] 请更新官方联机 Mod 至支持拓展页签的接口 v1 构建")
		return
	I18n.install()
	if not uses_external_client():
		_backend = Backend.new()
		add_child(_backend)
		_backend.prepared.connect(_on_prepared)
		_backend.failed.connect(func(message: String): failed.emit(message))
	if not _api.register_backend(ID, self):
		push_warning("[etn_coop_easytier] 拓展注册失败")
		return
	print("[etn_coop_easytier] extension ready api=1")

func uses_external_client() -> bool:
	return OS.has_feature("android")

func start(plan: Dictionary, hosting: bool) -> bool:
	if uses_external_client() or not is_instance_valid(_backend):
		return false
	# 会话凭据仅留在内存，不从可释放的表单取值，也不写入 diagnostics / 日志。
	var code := RoomCode.normalize(str(plan.get("room_code", "")))
	_room_code = RoomCode.format(code) if RoomCode.is_valid(code) else ""
	var accepted: bool = _backend.start(plan, hosting)
	if not accepted:
		_room_code = ""
	return accepted

func stop() -> void:
	_room_code = ""
	if is_instance_valid(_backend):
		_backend.stop()

func diagnostics() -> Dictionary:
	if uses_external_client():
		# 仅声明连接由外置客户端管理，不推测其 VPN 或游戏连接状态。
		return {"state": "external", "pid": 0}
	if not is_instance_valid(_backend):
		return {"state": "idle", "pid": 0}
	return _backend.diagnostics()

func start_connection(plan: Dictionary, hosting: bool) -> bool:
	# 官方 start_backend 会先关闭旧会话：Android 引导必须在此之前分流。
	if uses_external_client():
		return false
	return is_instance_valid(_api) and _api.start_backend(ID, plan, hosting)

func cancel_connection() -> void:
	if is_instance_valid(_api):
		_api.cancel(ID)

func _on_prepared(endpoint: Dictionary) -> void:
	if not _room_code.is_empty():
		endpoint["share_text"] = _room_code
		endpoint["share_label_key"] = "coop_et_room_code"
		prepared.emit(endpoint)
		return
	# 兼容只传网络名/密码、不使用房间码的程序化调用。
	var details: Dictionary = diagnostics()
	# 客机展示实际发现的房主地址（表单里的约定/回填地址只作回退）；诊断只含地址与端口，不含凭据。
	var host_ip: String = str(details.get("discovered_host_ip", ""))
	if host_ip.is_empty():
		host_ip = str(details.get("host_ip", ""))
	endpoint["share_text"] = "%s:%d" % [host_ip, int(details.get("game_port", 0))]
	prepared.emit(endpoint)

func create_menu_page() -> Control:
	# 页面归官方菜单持有，后端仍归 entry 持有；隐藏/释放 UI 不停止连接。
	# 官方 PageScroll 统一滚动：只返回内容高度的普通容器，不再自套滚动区或固定高度。
	var page: VBoxContainer = ExternalPage.new() if uses_external_client() else Page.new()
	page.name = "EasyTierPage"
	page.controller = self
	return page

func _exit_tree() -> void:
	stop()
