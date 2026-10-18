extends Node

## EasyTier no-TUN 后台组网。只管理自己启动的进程；ready 后由连接层建立 ENet。
## stop 幂等；ENet 重连不调用 stop。凭据不进入命令行、游戏日志或持久设置。
signal prepared(endpoint: Dictionary)
signal failed(status_key: String)

# EasyTier api_instance.proto: CONNECTED=0 / DISCONNECTED=1 / CONNECTING=2。
const CONNECTOR_CONNECTED: int = 0

# 房主把游戏端口编进 hostname，客机据此在 peer 表里认出房主并取虚拟 IP —— 客机不需要知道也不需要输入房主 IP。
const HOST_PREFIX: String = "etn-server-"
# 房间码流程的约定房主地址：客机先用它建立启动期静态转发（首包不丢），再用 peer 表核对真实地址。
const ASSUMED_HOST_IP: String = "10.144.144.1"
# 端口默认值：与本体 ENet 端口/组网监听端口保持一致。
const DEFAULT_GAME_PORT: int = 24591
const DEFAULT_LISTEN_PORT: int = 11010
# core_path 留空时的自动查找位置（相对游戏可执行文件目录与 user://），cli 必须与 core 同目录。
const CORE_SEARCH_SUBDIRS: Array[String] = [".", "easytier", "bin", "tools", "easytier-windows-x86_64"]
# 随包分发的工具目录：zip 内的 tools/<平台>/ 装到 user://mods/<id>/tools/<平台>/。
const MOD_TOOLS_SUBPATH: String = "mods/etn_coop_easytier"
# 临时凭据配置目录：本拓展自己的持久目录（user://），文件名随机；不再写系统缓存目录。
const CONFIG_DIR: String = "user://etn_easytier"
# 临时配置文件名前缀：新目录与旧版缓存目录共用，清扫遗留文件时按此前缀匹配。
const CONFIG_PREFIX: String = "etn-easytier-"
# 客机动态添加转发的两个阶段：先 add，再用 list 确认规则真的存在。
const ACTION_ADD: String = "add"
const ACTION_VERIFY: String = "verify"

const ENV_KEYS := [
	"ET_ACCEPT_DNS", "ET_BIND_DEVICE", "ET_COMPRESSION", "ET_CONFIG_DIR",
	"ET_CONFIG_FILE", "ET_CONFIG_SERVER", "ET_CONSOLE_LOG_LEVEL", "ET_CREDENTIAL",
	"ET_CREDENTIAL_FILE", "ET_DEFAULT_PROTOCOL", "ET_DEV_NAME", "ET_DHCP",
	"ET_DISABLE_ENCRYPTION", "ET_DISABLE_IPV6", "ET_DISABLE_KCP_INPUT", "ET_DISABLE_P2P",
	"ET_DISABLE_QUIC_INPUT", "ET_DISABLE_RELAY_KCP", "ET_DISABLE_RELAY_QUIC", "ET_DISABLE_SYM_HOLE_PUNCHING",
	"ET_DISABLE_TCP_HOLE_PUNCHING", "ET_DISABLE_UDP_HOLE_PUNCHING", "ET_DISABLE_UPNP", "ET_ENABLE_EXIT_NODE",
	"ET_ENABLE_KCP_PROXY", "ET_ENABLE_QUIC_PROXY", "ET_ENABLE_RELAY_FOREIGN_NETWORK_KCP", "ET_ENABLE_RELAY_FOREIGN_NETWORK_QUIC",
	"ET_ENABLE_UDP_BROADCAST_RELAY", "ET_ENCRYPTION_ALGORITHM", "ET_EXIT_NODES", "ET_EXTERNAL_NODE",
	"ET_FILE_LOG_COUNT", "ET_FILE_LOG_DIR", "ET_FILE_LOG_LEVEL", "ET_FILE_LOG_SIZE",
	"ET_FOREIGN_RELAY_BPS_LIMIT", "ET_HOSTNAME", "ET_INSTANCE_NAME", "ET_INSTANCE_RECV_BPS_LIMIT",
	"ET_IPV4", "ET_IPV6", "ET_IPV6_PUBLIC_ADDR_AUTO", "ET_IPV6_PUBLIC_ADDR_PREFIX",
	"ET_IPV6_PUBLIC_ADDR_PROVIDER", "ET_LATENCY_FIRST", "ET_LAZY_P2P", "ET_LISTENERS",
	"ET_LOCAL_PRIVATE_KEY", "ET_LOCAL_PUBLIC_KEY", "ET_MACHINE_ID", "ET_MANUAL_ROUTES",
	"ET_MAPPED_LISTENERS", "ET_MTU", "ET_MULTI_THREAD", "ET_MULTI_THREAD_COUNT",
	"ET_NEED_P2P", "ET_NETWORK_NAME", "ET_NETWORK_SECRET", "ET_NO_LISTENER",
	"ET_NO_TUN", "ET_P2P_ONLY", "ET_PEERS", "ET_PORT_FORWARD",
	"ET_PRIVATE_MODE", "ET_PROXY_FORWARD_BY_SYSTEM", "ET_PROXY_NETWORKS", "ET_RELAY_ALL_PEER_RPC",
	"ET_RELAY_NETWORK_WHITELIST", "ET_RPC_PORTAL", "ET_RPC_PORTAL_WHITELIST", "ET_SECURE_MODE",
	"ET_SOCKS5", "ET_STUN_SERVERS", "ET_STUN_SERVERS_V6", "ET_TLD_DNS_ZONE",
	"ET_USE_SMOLTCP", "ET_VPN_PORTAL",
]

var state: String = "idle"
var _core: Dictionary = {}
var _query: Dictionary = {}
var _query_output: PackedByteArray = PackedByteArray()
var _config_path: String = ""
var _cli: String = ""
var _core_path: String = ""
var _core_bundled: bool = false
var _searched: Array[String] = []
var _host: bool = false
var _requires_entry: bool = false
var _entry_url: String = ""
var _host_ip: String = ""
var _own_ip: String = ""
var _node_name: String = ""
var _game_port: int = 24591
var _initial_game_port: int = 0
var _forward_port: int = 0
var _rpc_port: int = 0
var _deadline: int = 0
var _query_deadline: int = 0
var _next_query: int = 0
var _dhcp: bool = false
var _discover_host: bool = false
var _discovered_host_ip: String = ""
var _forward_added: bool = false
var _action: Dictionary = {}
var _action_kind: String = ""
var _action_output: PackedByteArray = PackedByteArray()
var _action_deadline: int = 0


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func start(plan: Dictionary, hosting: bool) -> bool:
	stop()
	# 上次被强杀时可能残留含凭据的临时 TOML：本次启动前先清扫（本拓展目录 + 旧版缓存目录）。
	_sweep_config_dir()
	if not (OS.has_feature("windows") or OS.has_feature("linux") or OS.has_feature("macos")):
		return _reject("coop_status_et_platform_failed")
	var explicit_core: String = str(plan.get("core_path", "")).strip_edges()
	if not _resolve_core(explicit_core):
		return _reject("coop_status_et_path_failed" if not explicit_core.is_empty() else "coop_status_et_not_found")
	_host = hosting
	# 端口缺失或为 0 一律回落到默认值：调用方（表单/测试）留空时不能因此被判定参数无效。
	_game_port = int(plan.get("port", DEFAULT_GAME_PORT))
	if _game_port <= 0:
		_game_port = DEFAULT_GAME_PORT
	# 房主把端口编进 hostname，客机据此认出房主并取虚拟 IP（无需玩家输入房主 IP）。
	_initial_game_port = _game_port
	_node_name = HOST_PREFIX + str(_game_port) if hosting \
		else "etn-" + str(plan.get("node_id", Crypto.new().generate_random_bytes(16).hex_encode())).sha256_text().substr(0, 16)
	_host_ip = str(plan.get("host_ip", "")).strip_edges()
	var requested_ip: String = str(plan.get("own_ip", "")).strip_edges()
	_dhcp = bool(plan.get("dhcp", false)) or requested_ip.is_empty()
	if hosting:
		# 房主默认固定 IP（客机转发目标可预期）；显式要求 dhcp 时才交给 EasyTier 自动分配。
		_own_ip = _host_ip if not _host_ip.is_empty() else "10.144.144.1"
		_host_ip = _own_ip
		_dhcp = bool(plan.get("dhcp", false))
		if _dhcp:
			_own_ip = ""
			_host_ip = ""
		elif not _valid_ipv4(_own_ip):
			return _reject("coop_status_et_config_failed")
		_discover_host = false
	else:
		# 客机：own_ip 留空 = DHCP；host_ip 留空 = 按约定地址先建静态转发，再核对真实房主地址。
		_discover_host = _host_ip.is_empty()
		if _discover_host:
			_host_ip = ASSUMED_HOST_IP
		elif not _valid_ipv4(_host_ip):
			return _reject("coop_status_et_config_failed")
		if _dhcp:
			_own_ip = ""
		else:
			_own_ip = requested_ip
			# 显式地址必须合法，且不得等于已知/约定的房主地址：重复虚拟 IP 无仲裁，会互相抢流量。
			if not _valid_ipv4(_own_ip) or _own_ip == _host_ip:
				return _reject("coop_status_et_config_failed")
	var listen_port: int = int(plan.get("listen_port", DEFAULT_LISTEN_PORT))
	if listen_port <= 0:
		listen_port = DEFAULT_LISTEN_PORT
	var seed: String = str(plan.get("seed", "")).strip_edges()
	_requires_entry = hosting and not seed.is_empty()
	var network: String = str(plan.get("network_name", "")).strip_edges()
	var secret: String = str(plan.get("network_secret", ""))
	if network.is_empty() or secret.is_empty() or _game_port < 1 or _game_port > 65535 or listen_port < 1 or listen_port > 65535:
		return _reject("coop_status_et_config_failed")
	if (not hosting and seed.is_empty()) or (not seed.is_empty() and not _valid_seed(seed)):
		return _reject("coop_status_et_seed_failed")
	var rpc := TCPServer.new()
	if rpc.listen(0, "127.0.0.1") != OK:
		return _reject("coop_status_et_launch_failed")
	_rpc_port = rpc.get_local_port()
	rpc.stop()
	var udp := PacketPeerUDP.new()
	if udp.bind(0, "127.0.0.1") != OK:
		return _reject("coop_status_et_launch_failed")
	_forward_port = udp.get_local_port()
	udp.close()
	# 凭据配置写进本拓展自己的持久目录（随机文件名），外部 core 只读启动期一次。
	var config_dir: String = ProjectSettings.globalize_path(CONFIG_DIR)
	if not DirAccess.dir_exists_absolute(config_dir):
		DirAccess.make_dir_recursive_absolute(config_dir)
	_config_path = config_dir.path_join(CONFIG_PREFIX + Crypto.new().generate_random_bytes(16).hex_encode() + ".toml")
	var file := FileAccess.open(_config_path, FileAccess.WRITE)
	if file == null:
		return _reject("coop_status_et_launch_failed")
	# JSON 字符串转义是 TOML basic string 的子集（排除控制字符）。
	if _has_control(network) or _has_control(secret):
		file.close()
		return _reject("coop_status_et_config_failed")
	file.store_string("[network_identity]\nnetwork_name = %s\nnetwork_secret = %s\n" % [JSON.stringify(network), JSON.stringify(secret)])
	file.close()
	var args := PackedStringArray(["--config-file", _config_path, "--disable-env-parsing", "--no-tun", "--bind-device", "false",
		"--disable-ipv6", "--disable-upnp", "--private-mode", "true", "--relay-network-whitelist",
		"--hostname", _node_name, "--rpc-portal", "127.0.0.1:%d" % _rpc_port, "--console-log-level", "warn"])
	# DHCP 与显式 IPv4 互斥：客机默认走 DHCP（EasyTier 自行挑选空闲地址并在冲突时改址）。
	if _dhcp:
		args.append("--dhcp")
	else:
		args.append_array(["--ipv4", _own_ip])
	if hosting:
		args.append_array(["--listeners", "udp://%s:%d" % ["127.0.0.1" if plan.get("local_only", false) else "0.0.0.0", listen_port]])
	else:
		args.append("--no-listener")
		# 客机始终带一条静态转发（首包不丢）；若核对出的房主地址与约定不符，运行期再补一条。
		args.append_array(["--port-forward", "udp://127.0.0.1:%d/%s:%d" % [_forward_port, _host_ip, _game_port]])
	if not seed.is_empty():
		args.append_array(["--peers", seed])
	if plan.get("local_only", false):
		args.append_array(["--stun-servers", "--stun-servers-v6", "--disable-udp-hole-punching", "--disable-tcp-hole-punching"])
	# EasyTier CLI 的 ET_* 环境可覆盖配置；只在同步创建子进程期间隔离并立即还原。
	var env: Dictionary = {}
	for key in ENV_KEYS:
		if OS.has_environment(key):
			env[key] = OS.get_environment(key)
			OS.unset_environment(key)
	_core = OS.execute_with_pipe(_core_path, args, false)
	for key in env:
		OS.set_environment(key, env[key])
	if _core.is_empty():
		return _reject("coop_status_et_launch_failed")
	state = "preparing"
	_deadline = Time.get_ticks_msec() + int(plan.get("prepare_timeout_msec", 25000))
	_next_query = 0
	print("[etn_coop_easytier] EasyTier preparing pid=%d host=%s core=%s" % [_core_pid(), hosting, "bundled" if _core_bundled else "external"])
	return true


func stop() -> void:
	_finish_process(_query)
	_finish_process(_action)
	_finish_process(_core)
	_query_output.clear()
	_action_output.clear()
	_remove_config()
	_requires_entry = false
	_entry_url = ""
	_discover_host = false
	_discovered_host_ip = ""
	_forward_added = false
	_action_kind = ""
	# 保留刚发生的失败态给 UI/调用方看（仍只做进程/端口/临时文件清理），下次 start 才回到 preparing。
	if state != "failed":
		state = "idle"


func _core_pid() -> int:
	# 进程句柄在 stop/_finish_process 后会被清空；_core 是 Dictionary 而非 Object，不能用 is_instance_valid()。
	return int(_core.get("pid", 0))


func diagnostics() -> Dictionary:
	return {"state": state, "pid": _core_pid(), "ip": _own_ip, "host_ip": _host_ip,
		"game_port": _game_port, "forward_port": _forward_port, "dhcp": _dhcp,
		"discovered_host_ip": _discovered_host_ip, "forward_added": _forward_added,
		"forward_target": _discovered_host_ip if _forward_added else _host_ip,
		"core_path": _core_path, "core_bundled": _core_bundled, "searched": _searched.size()}


func _process(_delta: float) -> void:
	if state != "preparing" and state != "ready":
		return
	_drain(_core) # 丢弃原始子进程日志，防止其输出完整配置/凭据。
	var core_pid: int = _core_pid()
	if core_pid <= 0 or not OS.is_process_running(core_pid):
		_reject("coop_status_et_process_failed")
		return
	if state == "ready":
		return
	var now: int = Time.get_ticks_msec()
	if now >= _deadline:
		_reject("coop_status_et_timeout_failed")
		return
	if not _action.is_empty():
		_step_action(now)
		return
	if _query.is_empty():
		if now < _next_query:
			return
		_query_output.clear()
		var query_args := PackedStringArray(["-p", "127.0.0.1:%d" % _rpc_port, "-o", "json"])
		# 先取唯一入口的规范 URL，再核对该入口的已建立路由与连接。
		if _requires_entry:
			query_args.append_array(["connector", "list"] if _entry_url.is_empty() else ["-v", "peer"])
		else:
			query_args.append("peer")
		_query = OS.execute_with_pipe(_cli, query_args, false)
		_query_deadline = now + 2500
		_next_query = now + 500
		return
	_query_output.append_array(_drain(_query, true))
	if _query_output.size() > 262144 or now >= _query_deadline:
		_finish_process(_query)
		return
	if OS.is_process_running(int(_query.pid)):
		return
	_query_output.append_array(_drain(_query, true))
	# RPC 未就绪/节点变化时 CLI 可返回非 JSON；准备轮询允许重试，不刷引擎 ERROR。
	var parser := JSON.new()
	var parse_error: Error = parser.parse(_query_output.get_string_from_utf8())
	_finish_process(_query)
	if parse_error != OK:
		return
	var peers = parser.data
	if not peers is Array:
		return
	var found: bool = _host
	if _requires_entry:
		if _entry_url.is_empty():
			_entry_url = _connected_entry_url(peers)
			if not _entry_url.is_empty():
				_next_query = now
			return
		found = _entry_has_route(peers)
		_entry_url = "" # 每轮重新确认 connector，重试不沿用上次成功状态。
	if not _host:
		# DHCP 客机在 peer 表出现房主时可能还没分到本机地址，此时转发不通：等地址就绪再进入 ready。
		if not _local_address_ready(peers):
			return
		if _discover_host:
			# 房主 IP 由 hostname 广播：核对约定地址；不一致时才运行期补转发（新规则首包可能丢，ENet 会重试）。
			var host_peer: Dictionary = _host_peer_from(peers)
			if host_peer.is_empty():
				return
			_discovered_host_ip = str(host_peer.get("ip", ""))
			_game_port = int(host_peer.get("port", _game_port))
			if not _dhcp and _own_ip == _discovered_host_ip:
				# 重复虚拟 IP 无仲裁，必须立刻退出。
				_reject("coop_status_et_duplicate_failed")
				return
			if _discovered_host_ip != _host_ip or _game_port != _initial_game_port:
				if not _forward_added:
					# 保留启动规则，用新 bind 隔离目标变化；同 bind 追加规则会仍命中旧目标。
					# 为已发现的完整目标使用新回环端口，旧规则随本拓展 core 退出统一释放。
					var udp := PacketPeerUDP.new()
					if udp.bind(0, "127.0.0.1") != OK:
						_reject("coop_status_et_transport_failed")
						return
					_forward_port = udp.get_local_port()
					udp.close()
					_start_action(ACTION_ADD)
					return
			found = true
		else:
			for peer in peers:
				if peer is Dictionary and str(peer.get("cost", "")).to_lower() == "local":
					continue
				# peer 表包含暂存路由，不据此判定其它客机 IP 冲突；由表单要求分配唯一地址。
				if peer is Dictionary and str(peer.get("ipv4", "")) == _host_ip:
					found = true
	if not found:
		return
	state = "ready"
	_remove_config()
	print("[etn_coop_easytier] EasyTier ready pid=%d host=%s" % [_core_pid(), _host])
	prepared.emit({"ip": "127.0.0.1", "port": _game_port if _host else _forward_port, "host": _host})


func _connected_entry_url(connectors: Array) -> String:
	# 每次启动独立 core，仅通过 --peers 添加一个入口，且禁用环境配置。
	# connector 同时覆盖同网私有节点与无虚拟 IP 的共享节点，不依赖游戏客机在线。
	if connectors.size() != 1 or not connectors[0] is Dictionary:
		return ""
	var connector: Dictionary = connectors[0]
	var url = connector.get("url")
	var status = connector.get("status")
	if url is Dictionary and url.get("url") is String \
		and (status is int or status is float) and status == CONNECTOR_CONNECTED:
		return url.url
	return ""


func _entry_has_route(peers: Array) -> bool:
	# 2.6.4 在错误密码下也可能报告 connector CONNECTED，但无可通信的路由。
	# 使用 verbose peer 关联入口 URL；其它入站客机/缓存路由不能替入口放行。
	for pair in peers:
		if not pair is Dictionary:
			continue
		var route = pair.get("route")
		var peer = pair.get("peer")
		if not route is Dictionary or route.get("cost") != 1 or not peer is Dictionary:
			continue
		var connections = peer.get("conns")
		if not connections is Array:
			continue
		for connection in connections:
			if not connection is Dictionary or connection.get("is_client") != true or connection.get("is_closed") != false:
				continue
			var tunnel = connection.get("tunnel")
			if not tunnel is Dictionary:
				continue
			var remote = tunnel.get("remote_addr")
			if remote is Dictionary and remote.get("url") == _entry_url:
				return true
	return false


func _resolve_core(explicit_path: String) -> bool:
	# 顺序：显式路径（高级选项）→ 随包分发的 tools/<平台>/ → mod 根目录 → 游戏目录 → user:// 常见子目录。
	# cli 必须与 core 同目录；Windows 之外补执行位（zip 解压不带 +x）。
	_searched.clear()
	_core_path = ""
	_cli = ""
	_core_bundled = false
	var windows: bool = OS.has_feature("windows")
	var core_name: String = "easytier-core.exe" if windows else "easytier-core"
	var cli_name: String = "easytier-cli.exe" if windows else "easytier-cli"
	var candidates: Array[String] = []
	if not explicit_path.is_empty():
		candidates.append(explicit_path)
	var mod_root: String = OS.get_user_data_dir().path_join(MOD_TOOLS_SUBPATH)
	var tools_root: String = mod_root.path_join("tools")
	if DirAccess.dir_exists_absolute(tools_root):
		for sub in DirAccess.get_directories_at(tools_root):
			candidates.append(tools_root.path_join(sub).path_join(core_name))
	candidates.append(mod_root.path_join(core_name))
	for root in [OS.get_executable_path().get_base_dir(), OS.get_user_data_dir()]:
		for sub in CORE_SEARCH_SUBDIRS:
			candidates.append(root.path_join(core_name) if sub == "." else root.path_join(sub).path_join(core_name))
	for candidate in candidates:
		var path: String = candidate
		if DirAccess.dir_exists_absolute(path):
			path = path.path_join(core_name)
		if not path.is_absolute_path():
			continue
		if not _searched.has(path):
			_searched.append(path)
		if FileAccess.file_exists(path) and FileAccess.file_exists(path.get_base_dir().path_join(cli_name)):
			_core_path = path
			_cli = path.get_base_dir().path_join(cli_name)
			_core_bundled = path.begins_with(mod_root)
			if not windows:
				_ensure_executable(_core_path)
				_ensure_executable(_cli)
			return true
	return false


func _ensure_executable(path: String) -> void:
	# 捆绑的二进制来自 zip，解压后没有执行位；chmod 失败不阻断（可能本来就带 +x 或文件系统只读）。
	OS.execute("chmod", PackedStringArray(["+x", path]))


func _local_address_ready(peers: Array) -> bool:
	# peer 表里的本机条目（cost=Local）带自己的虚拟地址；DHCP 模式下它会在分配完成后才出现。
	for peer in peers:
		if peer is Dictionary and str(peer.get("cost", "")).to_lower() == "local":
			return _valid_ipv4(str(peer.get("ipv4", "")))
	return false


func _host_peer_from(peers: Array) -> Dictionary:
	# 房主 hostname = etn-server-<游戏端口>：据此取房主虚拟 IP 与端口，客机无需输入房主 IP。
	for peer in peers:
		if not peer is Dictionary or str(peer.get("cost", "")).to_lower() == "local":
			continue
		var hostname: String = str(peer.get("hostname", ""))
		if not hostname.begins_with(HOST_PREFIX):
			continue
		var port_text: String = hostname.substr(HOST_PREFIX.length())
		var ip: String = str(peer.get("ipv4", ""))
		if not port_text.is_valid_int() or not _valid_ipv4(ip):
			continue
		return {"ip": ip, "port": port_text.to_int()}
	return {}


func _start_action(kind: String) -> void:
	# 运行期用 CLI 管理转发规则；两阶段：add 之后用 list 确认，不依赖 CLI 文本/退出码。
	_action_output.clear()
	_action_kind = kind
	_action_deadline = Time.get_ticks_msec() + 4000
	var args := PackedStringArray(["-p", "127.0.0.1:%d" % _rpc_port])
	if kind == ACTION_ADD:
		args.append_array(["port-forward", "add", "udp", "127.0.0.1:%d" % _forward_port,
			"%s:%d" % [_discovered_host_ip, _game_port]])
	else:
		args.append_array(["-o", "json", "port-forward", "list"])
	_action = OS.execute_with_pipe(_cli, args, false)
	if _action.is_empty():
		_action_kind = ""
		_reject("coop_status_et_transport_failed")


func _step_action(now: int) -> void:
	_action_output.append_array(_drain(_action, true))
	if OS.is_process_running(int(_action.pid)):
		if now >= _action_deadline:
			_finish_process(_action)
			_action_kind = ""
			_reject("coop_status_et_transport_failed")
		return
	_action_output.append_array(_drain(_action, true))
	var kind: String = _action_kind
	var output: String = _action_output.get_string_from_utf8()
	_finish_process(_action)
	_action_kind = ""
	_action_output.clear()
	if kind == ACTION_ADD:
		_start_action(ACTION_VERIFY)
		return
	_forward_added = _forward_present(output)
	_next_query = now # 规则确认后立即复查 peer 并进入 ready；失败则等下一轮重试（总超时兜底）。
	if not _forward_added:
		print("[etn_coop_easytier] EasyTier forward not confirmed, retrying")


func _forward_present(output: String) -> bool:
	var parser := JSON.new()
	if parser.parse(output) != OK or not parser.data is Dictionary:
		return false
	var configs = parser.data.get("cfgs")
	if not configs is Array:
		return false
	for config in configs:
		if config is Dictionary and config.get("bind_addr") is Dictionary \
			and int(config.bind_addr.get("port", 0)) == _forward_port \
			and config.get("socket_type") == 1 and config.get("dst_addr") is Dictionary:
			var dst: Dictionary = config.dst_addr
			var ip = dst.get("ip", {}).get("Ipv4", {})
			var expected_ip := 0
			for octet in _discovered_host_ip.split("."):
				expected_ip = (expected_ip << 8) | octet.to_int()
			if int(dst.get("port", 0)) == _game_port and int(ip.get("addr", -1)) == expected_ip:
				return true
	return false


func _drain(process: Dictionary, capture: bool = false) -> PackedByteArray:
	var output := PackedByteArray()
	for key in ["stdio", "stderr"]:
		var pipe = process.get(key)
		if pipe != null and pipe.is_open():
			var bytes: PackedByteArray = pipe.get_buffer(65536)
			if capture and key == "stdio":
				output.append_array(bytes)
	return output


func _finish_process(process: Dictionary) -> void:
	var pid: int = int(process.get("pid", 0))
	if pid > 0 and OS.is_process_running(pid):
		OS.kill(pid)
	for key in ["stdio", "stderr"]:
		var pipe = process.get(key)
		if pipe != null and pipe.is_open():
			pipe.close()
	process.clear()


func _sweep_config_dir() -> void:
	# 遗留文件含组网名称与密码：启动前只按本拓展的文件名前缀清扫自己产生的 TOML。
	var dirs: Array[String] = [ProjectSettings.globalize_path(CONFIG_DIR), OS.get_cache_dir()]
	for dir in dirs:
		if not DirAccess.dir_exists_absolute(dir):
			continue
		for file_name in DirAccess.get_files_at(dir):
			if file_name.begins_with(CONFIG_PREFIX) and file_name.ends_with(".toml"):
				DirAccess.remove_absolute(dir.path_join(file_name))


func _remove_config() -> void:
	if not _config_path.is_empty() and FileAccess.file_exists(_config_path):
		DirAccess.remove_absolute(_config_path)
	_config_path = ""


func _reject(key: String) -> bool:
	stop()
	state = "failed"
	print("[etn_coop_easytier] EasyTier failed: %s" % key)
	failed.emit(key)
	return false


func _valid_ipv4(ip: String) -> bool:
	return ip.is_valid_ip_address() and ip.count(".") == 3 and not ip.begins_with("127.") and ip != "0.0.0.0" and ip != "255.255.255.255"


func _has_control(value: String) -> bool:
	for character in value:
		if character.unicode_at(0) < 32:
			return true
	return false


func _valid_seed(seed: String) -> bool:
	if _has_control(seed) or seed.contains(" ") or seed.contains("@"):
		return false
	for prefix in ["udp://", "tcp://", "ws://", "wss://"]:
		if seed.begins_with(prefix) and seed.length() > prefix.length():
			return true
	return false


func _exit_tree() -> void:
	stop()
