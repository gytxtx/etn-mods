extends Node

## 修改器核心：数值注入、资源/解锁/调试动作、界面偏好持久化。
##
## 数值注入走 PlayerData.player_ability_changed_end（每次属性重算结束后触发）：
## 重算会把 stats 从 base_* / *_mult 重新推导一遍，所以在回调里"再乘一次倍率"
## 天然是幂等的，不需要记录上次注入了多少，也不会吞掉本局的自然成长。

signal state_changed
signal notice(text: String)
## 作弊值被整体重置（进入联机房间 / 手动关闭全部作弊）后发出，供面板同步控件。
signal cheats_reset

const CFG_PATH := "user://etn_trainer.cfg"

# ---- 数值作弊（每次启动归零） ----
var speed_mult: float = 1.0
var fire_rate_mult: float = 1.0
var damage_mult: float = 1.0
var pickup_mult: float = 1.0
var armor_cap: float = -1.0   # 额外减伤上限（叠加在角色原始 armor_cap 上）；<0 = 不覆盖
var armor_add: float = 0.0    # 护甲值(hurt_resis)加算
var _base_armor_cap: float = -1.0
var _base_cap_player: Node = null
var invincible: bool = false
var one_hit_kill: bool = false

# ---- dev_mode（只改内存，不写 config.ini） ----
var dev_mode_on: bool = false
var dev_mode_locked: bool = false

# ---- 界面偏好（持久化） ----
var panel_pos: Vector2 = Vector2(-99999.0, -99999.0)
var hud_on: bool = false

var _tick: float = 0.0
var _lan_active: bool = false


func setup() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not PlayerData.player_ability_changed_end.is_connected(_on_recomputed):
		PlayerData.player_ability_changed_end.connect(_on_recomputed)
	dev_mode_on = Game.dev_mode
	dev_mode_locked = Game.dev_mode
	_load_prefs()


# ================= 数值注入 =================

func _on_recomputed() -> void:
	var p = PlayerData.player
	if p == null or not is_instance_valid(p):
		return
	var s = p.get("stats")
	if s == null:
		return
	if not is_equal_approx(speed_mult, 1.0):
		s.MAX_SPEED = int(round(clampf(float(s.MAX_SPEED) * speed_mult, 50.0, float(PlayerData.MAX_SPEED_value))))
	if not is_equal_approx(fire_rate_mult, 1.0):
		var rpm: int = int(round(float(s.bullet_shoot_time) * fire_rate_mult))
		s.bullet_shoot_time = mini(rpm, PlayerData.max_bullet_shoot_time)
	if not is_equal_approx(damage_mult, 1.0):
		s.global_damage = maxf(0.01, float(s.global_damage) * damage_mult)
	if not is_equal_approx(pickup_mult, 1.0):
		s.pick_up_range = maxi(1, int(round(float(s.pick_up_range) * pickup_mult)))
		s.pick_up_range_changed.emit()
	if armor_add > 0.0:
		s.hurt_resis = int(round(float(s.hurt_resis) + armor_add))


## 任一作弊值变化后调用：触发本体重算，由 _on_recomputed 把倍率乘上去。
func push_values() -> void:
	var p = PlayerData.player
	if p != null and is_instance_valid(p):
		PlayerData.update_player_ability()
	_reassert()
	state_changed.emit()


func _process(delta: float) -> void:
	# 进入联机房间（is_lan_session 变为 true）时立即清空本局作弊，避免带进他人房间。
	var lan: bool = is_locked()
	if lan and not _lan_active:
		_lan_active = true
		reset_cheats(true, "已进入联机房间，作弊功能已重置")
	elif not lan:
		_lan_active = false

	_tick += delta
	if _tick < 0.5:
		return
	_tick = 0.0
	_reassert()


## 整体重置本局作弊：倍率、护甲、无敌、秒杀、内存 dev_mode，并重算玩家属性。
func reset_cheats(notify: bool = false, reason: String = "已关闭全部作弊") -> void:
	speed_mult = 1.0
	fire_rate_mult = 1.0
	damage_mult = 1.0
	pickup_mult = 1.0
	armor_cap = -1.0
	armor_add = 0.0
	invincible = false
	one_hit_kill = false
	Game.one_hit_kill = false
	if not dev_mode_locked:
		dev_mode_on = false
		Game.dev_mode = false
	var p = get_player()
	if p != null:
		var hc = p.get("health_component")
		if hc != null:
			hc.is_invincible = false
	# 让本体重算属性：倍率归 1 后自然还原，并恢复原始护甲上限。
	push_values()
	cheats_reset.emit()
	if notify:
		notice.emit(reason)


## 每 0.5s 兜底：玩家节点重建 / 换角色后重新施加"开关型"作弊。
func _reassert() -> void:
	var p = get_player()
	if p == null:
		return
	if one_hit_kill:
		Game.one_hit_kill = true
	var hc = p.get("health_component")
	if hc == null:
		return
	if invincible and hc.is_invincible == false:
		hc.is_invincible = true
	# 减伤上限：以第一次看到的角色原始 armor_cap 为基准叠加，避免覆盖后无法还原
	if _base_cap_player != p:
		_base_cap_player = p
		_base_armor_cap = float(hc.get("armor_cap"))
	if armor_cap >= 0.0:
		var target: float = clampf(_base_armor_cap + armor_cap, 0.0, 0.98)
		if not is_equal_approx(float(hc.get("armor_cap")), target):
			hc.armor_cap = target
	elif _base_armor_cap >= 0.0 and not is_equal_approx(float(hc.get("armor_cap")), _base_armor_cap):
		hc.armor_cap = _base_armor_cap


# ================= 查询 =================

func get_player() -> Node:
	var t := get_tree()
	if t == null:
		return null
	return t.get_first_node_in_group("Player")


func get_round_timer() -> Node:
	var cs := get_tree().current_scene if get_tree() != null else null
	if cs == null:
		return null
	return cs.get_node_or_null("RoundTimer")


func get_enemy_manager() -> Node:
	var cs := get_tree().current_scene if get_tree() != null else null
	if cs == null:
		return null
	return cs.get_node_or_null("EnemyManager")


func in_game() -> bool:
	return get_player() != null


## 当前玩家的一帧只读快照，供面板显示「实际数值」与生命条。
func snapshot() -> Dictionary:
	var p = get_player()
	if p == null or not is_instance_valid(p):
		return {}
	var s = p.get("stats")
	if s == null:
		return {}
	var out := {
		"speed": int(s.MAX_SPEED),
		"rpm": int(s.bullet_shoot_time),
		"damage": float(s.global_damage),
		"pickup": int(s.pick_up_range),
		"hp": int(s.hp),
		"max_hp": int(s.max_hp),
		"armor": int(s.hurt_resis),
	}
	var hc = p.get("health_component")
	if hc != null:
		out["armor_cap"] = float(hc.get("armor_cap"))
	return out


func get_coin() -> int:
	var p = get_player()
	if p == null or p.get("stats") == null:
		return -1
	return int(p.stats.coin)


func get_pyroxenes() -> int:
	return int(PlayerData.player_pyroxenes)


func is_locked() -> bool:
	if ExtensionHooks.is_lan_session.is_valid():
		return bool(ExtensionHooks.is_lan_session.call())
	return false


# ================= 开关型作弊 =================

func set_invincible(on: bool) -> void:
	invincible = on
	var p = get_player()
	if p != null:
		var hc = p.get("health_component")
		if hc != null:
			hc.is_invincible = on
	state_changed.emit()


func set_one_hit_kill(on: bool) -> void:
	one_hit_kill = on
	Game.one_hit_kill = on
	state_changed.emit()


func set_dev_mode(on: bool) -> void:
	if dev_mode_locked:
		return
	dev_mode_on = on
	Game.dev_mode = on
	state_changed.emit()


# ================= 资源 =================

func add_coin(amount: int) -> void:
	var p = get_player()
	if p == null or p.get("stats") == null:
		notice.emit("当前没有玩家，无法加金币")
		return
	p.stats.coin += amount
	notice.emit("金币 %+d → %d" % [amount, p.stats.coin])


func add_pyroxenes(amount: int) -> void:
	PlayerData.player_pyroxenes += amount
	notice.emit("青辉石 %+d → %d" % [amount, PlayerData.player_pyroxenes])


# ================= 解锁 =================

func unlock_all() -> void:
	var n_char := _unlock_characters()
	var n_cloth := _unlock_clothes()
	var n_support := _unlock_supports()
	var n_group := _unlock_groups()
	Game.save_playerdata()
	GameEvents.emit_check_data()
	notice.emit("已解锁：角色 %d / 服装 %d / 支援 %d / 社团 %d" % [n_char, n_cloth, n_support, n_group])
	state_changed.emit()


## 解锁进度（拥有 / 总数），用于「解锁」页的进度展示。
func unlock_progress() -> Dictionary:
	return {
		"characters": _progress_characters(),
		"clothes": _progress_clothes(),
		"supports": _progress_supports(),
		"groups": _progress_groups(),
	}


func _progress_groups() -> Dictionary:
	var ids := {}
	for s in _all_societies():
		if s != null:
			var gid := str(s.get("group_id", ""))
			if gid != "":
				ids[gid] = true
	var owned := 0
	for gid in ids.keys():
		if PlayerData.group.has(gid):
			owned += 1
	return {"owned": owned, "total": ids.size()}


## 本体角色 + Mod 角色（本体角色不在 ModAPI.get_characters() 里）。
func _all_character_cards() -> Array:
	var cards := []
	cards.append_array(ModAPI.get_base_characters())
	cards.append_array(ModAPI.get_characters())
	return cards


func _progress_characters() -> Dictionary:
	var ids := {}
	for card in _all_character_cards():
		if card != null:
			ids[str(card.get("id"))] = true
	var owned := 0
	for id in ids.keys():
		if PlayerData.character.has(id):
			owned += 1
	return {"owned": owned, "total": ids.size()}


func _progress_clothes() -> Dictionary:
	var ids := {}
	for card in _all_cloth_cards():
		if card == null:
			continue
		var cid := str(card.get("id"))
		if cid != "":
			ids[cid] = true
	var owned_ids := {}
	for key in PlayerData.clothes_group.keys():
		for cid in PlayerData.clothes_group[key]:
			owned_ids[str(cid)] = true
	var owned := 0
	for cid in ids.keys():
		if owned_ids.has(cid):
			owned += 1
	return {"owned": owned, "total": ids.size()}


func _progress_supports() -> Dictionary:
	var ids := {}
	for card in SupportData.support_pool:
		if card != null:
			ids[str(card.get("support_id"))] = true
	var owned := 0
	for sid in ids.keys():
		if SupportData.support_data.has(sid):
			owned += 1
	return {"owned": owned, "total": ids.size()}


func _unlock_characters() -> int:
	var added := 0
	for card in _all_character_cards():
		if card == null:
			continue
		if not PlayerData.character.has(card.id):
			PlayerData.character.push_back(card.id)
			added += 1
	return added


func _unlock_groups() -> int:
	var added := 0
	for s in _all_societies():
		var gid := str(s.get("group_id", ""))
		if gid != "" and not PlayerData.group.has(gid):
			PlayerData.group.push_back(gid)
			added += 1
	return added


func _all_societies() -> Array:
	var societies := []
	societies.append_array(ModAPI.get_base_societies())
	societies.append_array(ModAPI.get_societies())
	return societies


func _all_cloth_cards() -> Array:
	var cards := []
	cards.append_array(ModAPI.get_content("clothes"))
	cards.append_array(_load_dir_cards("res://resources/clothes", "ClothesCard", true))
	return cards


func _unlock_clothes() -> int:
	var cards := _all_cloth_cards()
	var added := 0
	for card in cards:
		if card == null:
			continue
		var id_name := str(card.get("id_name"))
		var cid := str(card.get("id"))
		if id_name == "" or cid == "":
			continue
		var group: Array = PlayerData.clothes_group.get(id_name, [])
		if not group.has(cid):
			group.push_back(cid)
			PlayerData.clothes_group[id_name] = group
			added += 1
	return added


func _unlock_supports() -> int:
	var added := 0
	for card in SupportData.support_pool:
		if card == null:
			continue
		if not SupportData.support_data.has(card.support_id):
			SupportData.add_new_data(card)
			added += 1
	return added


# ================= 辅助 =================

func heal_full() -> void:
	var p = get_player()
	if p == null or p.get("stats") == null:
		return
	var hc = p.get("health_component")
	var s = p.get("stats")
	if hc == null:
		s.hp = s.max_hp
		notice.emit("已回满血")
		return
	# is_invincible 会让治疗一起早退（player_health_component.gd:38），先临时关掉
	var was_inv: bool = hc.is_invincible
	hc.is_invincible = false
	var heal := HealData.fill(hc.heal_data, {
		"amount": maxi(1, int(s.max_hp)),
		"source": GameTags.PLAYER,
		"node": p,
	})
	hc.take_damage(heal)
	hc.is_invincible = was_inv
	notice.emit("已回满血")


# ================= 调试 =================

func clear_enemies() -> int:
	var killed := 0
	var p = get_player()
	for body in PoolManager.get_active_enemies():
		if body == null or not is_instance_valid(body):
			continue
		var hc = body.get("health_component")
		if hc == null:
			continue
		var hp: int = 1
		var st = body.get("stats")
		if st != null:
			hp = maxi(1, int(st.hp) + 1)
		hc.take_damage(DamageData.bullet(hp, Faction.PLAYER_SIDE, p))
		killed += 1
	notice.emit("已清场：%d 个敌人" % killed)
	return killed


func end_round() -> void:
	var rt = get_round_timer()
	if rt == null:
		notice.emit("当前场景没有回合计时器")
		return
	if rt.timer == null:
		return
	rt.timer.stop()
	rt.round_time = 0
	rt._on_timer_timeout()


func list_enemy_cards() -> Array:
	var out: Array = []
	out.append_array(ModAPI.get_content("enemies"))
	out.append_array(_load_dir_cards("res://resources/enemy", "EnemyCard", false))
	return out


func spawn_enemy(card) -> void:
	if card == null or card.body == null:
		return
	var root := get_tree().get_first_node_in_group("EnemiesRoot")
	if root == null:
		notice.emit("当前场景没有 EnemiesRoot")
		return
	var p = get_player()
	var base_pos: Vector2 = p.global_position if p != null else Vector2.ZERO
	var scene := load("res://script/spawn_anim.tscn")
	if scene == null:
		return
	var anim = scene.instantiate()
	anim.position = base_pos + Vector2(randf_range(-40.0, 40.0), randf_range(-40.0, 40.0))
	anim.hp_mult = 1
	anim.damage_mult = 1
	anim.process_mode = Node.PROCESS_MODE_ALWAYS
	root.add_child(anim)
	anim.enemy_spawn_anim(card)
	notice.emit("已生成：%s" % str(card.get("id")))


func _load_dir_cards(dir_path: String, class_name_check: String, recursive: bool) -> Array:
	var out: Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	_collect_cards(dir, dir_path, class_name_check, recursive, out, 0)
	return out


func _collect_cards(dir: DirAccess, dir_path: String, cls: String, recursive: bool, out: Array, depth: int) -> void:
	if depth > 3:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name.begins_with("."):
			name = dir.get_next()
			continue
		var full := dir_path + "/" + name
		if dir.current_is_dir():
			if recursive:
				var sub := DirAccess.open(full)
				if sub != null:
					_collect_cards(sub, full, cls, recursive, out, depth + 1)
		elif name.ends_with(".tres"):
			var res = load(full)
			if res != null and res.get_script() != null and str(res.get_script().get_global_name()) == cls:
				out.append(res)
		name = dir.get_next()
	dir.list_dir_end()


# ================= 偏好持久化 =================

func _load_prefs() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CFG_PATH) != OK:
		return
	panel_pos = Vector2(
		float(cfg.get_value("ui", "panel_x", -99999.0)),
		float(cfg.get_value("ui", "panel_y", -99999.0)))
	hud_on = bool(cfg.get_value("ui", "hud_on", false))


func save_prefs() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("ui", "panel_x", panel_pos.x)
	cfg.set_value("ui", "panel_y", panel_pos.y)
	cfg.set_value("ui", "hud_on", hud_on)
	cfg.save(CFG_PATH)
