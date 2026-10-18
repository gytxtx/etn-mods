extends CanvasLayer

## 修改器面板（纯代码构建，复用本体默认主题）。
## 注意：本体基准分辨率 640x360（窗口 720p 由 stretch=canvas_items 放大 2x），
## 所以所有尺寸/字号都按 640x360 设计，面板必须小于该视口。

const CoreScript := preload("res://mods/etn_trainer/core/trainer_core.gd")

const TABS := [
	["stats", "数值"],
	["res", "资源"],
	["unlock", "解锁"],
	["support", "辅助"],
	["debug", "调试"],
	["about", "关于"],
]

const F_TITLE := 13
const F_BODY := 9
const F_SMALL := 8

var core: Node = null
var hud: CanvasLayer = null

var _root: Control
var _dim: ColorRect
var _panel: Panel
var _margin: MarginContainer
var _col: VBoxContainer
var _body: HBoxContainer
var _banner: Label
var _toast: Label
var _toast_left: float = 0.0
var _hint: Label
var _pages_holder: MarginContainer
var _pages: Dictionary = {}
var _tab_buttons: Dictionary = {}
var _sliders: Dictionary = {}
var _checks: Dictionary = {}
var _current_tab: String = "stats"

var _confirm_bar: PanelContainer
var _confirm_label: Label
var _confirm_cb: Callable = Callable()

var _enemy_cards: Array = []
var _enemy_option: OptionButton = null
var _status: Label = null
var _countdown_label: Label = null

var _syncing: bool = false
var _paused_by_us: bool = false
var _self_lock: bool = false
var _external_lock: bool = false
var _prev_mouse: int = Input.MOUSE_MODE_VISIBLE
var _dragging: bool = false
var _drag_off: Vector2 = Vector2.ZERO
var _tick: float = 0.0


func _ready() -> void:
	layer = 200
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_show_tab("stats")


func _exit_tree() -> void:
	if _paused_by_us and not _external_lock:
		_paused_by_us = false
		var t := get_tree()
		if t != null:
			t.paused = false
			_self_lock = true
			GameEvents.emit_pause_lock(false)
			_self_lock = false
		Input.mouse_mode = _prev_mouse


# ============================================================ 构建

func _build() -> void:
	_root = Control.new()
	_root.name = "TrainerRoot"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_dim = ColorRect.new()
	_dim.name = "Dim"
	_dim.color = Color(0, 0, 0, 0.55)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_dim)

	_panel = Panel.new()
	_panel.name = "Panel"
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.size = Vector2(600, 336)
	_panel.position = Vector2(20, 12)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.07, 0.10, 0.97)
	sb.border_color = Color(0.45, 0.70, 0.95, 0.9)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.gui_input.connect(_on_panel_input)
	_root.add_child(_panel)

	_margin = MarginContainer.new()
	_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		_margin.add_theme_constant_override("margin_" + side, 6)
	for side in ["top", "bottom"]:
		_margin.add_theme_constant_override("margin_" + side, 4)
	_panel.add_child(_margin)

	_col = VBoxContainer.new()
	_col.add_theme_constant_override("separation", 3)
	_margin.add_child(_col)

	# ---- 标题栏（可拖动）----
	var header := HBoxContainer.new()
	header.name = "Header"
	header.mouse_filter = Control.MOUSE_FILTER_STOP
	header.add_theme_constant_override("separation", 4)
	header.gui_input.connect(_on_header_input)
	_col.add_child(header)

	var title := Label.new()
	title.text = "修改器"
	title.add_theme_font_size_override("font_size", F_TITLE)
	header.add_child(title)

	var ver := Label.new()
	ver.text = "etn_trainer 0.1.0"
	ver.add_theme_font_size_override("font_size", F_SMALL)
	ver.modulate = Color(1, 1, 1, 0.55)
	header.add_child(ver)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(spacer)

	_hint = Label.new()
	_hint.text = "F1 关闭"
	_hint.add_theme_font_size_override("font_size", F_SMALL)
	_hint.modulate = Color(1, 1, 1, 0.65)
	header.add_child(_hint)

	var close := Button.new()
	close.text = "关闭"
	close.add_theme_font_size_override("font_size", F_SMALL)
	close.pressed.connect(close_panel)
	header.add_child(close)

	# ---- 顶部提示条 ----
	_banner = Label.new()
	_banner.visible = false
	_banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_banner.add_theme_font_size_override("font_size", F_SMALL)
	_banner.add_theme_color_override("font_color", Color(1.0, 0.72, 0.4))
	_col.add_child(_banner)

	# ---- 操作反馈 ----
	_toast = Label.new()
	_toast.visible = false
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast.add_theme_font_size_override("font_size", F_SMALL)
	_toast.add_theme_color_override("font_color", Color(0.72, 1.0, 0.78))
	_col.add_child(_toast)

	# ---- 主体 ----
	_body = HBoxContainer.new()
	_body.name = "Body"
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 6)
	_col.add_child(_body)

	var tabs := VBoxContainer.new()
	tabs.name = "Tabs"
	tabs.custom_minimum_size = Vector2(58, 0)
	tabs.add_theme_constant_override("separation", 2)
	_body.add_child(tabs)
	for entry in TABS:
		var b := Button.new()
		b.text = str(entry[1])
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", F_BODY)
		b.size_flags_vertical = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_show_tab.bind(str(entry[0])))
		tabs.add_child(b)
		_tab_buttons[str(entry[0])] = b

	_pages_holder = MarginContainer.new()
	_pages_holder.name = "Pages"
	_pages_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pages_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_child(_pages_holder)

	_build_stats_page()
	_build_resource_page()
	_build_unlock_page()
	_build_support_page()
	_build_debug_page()
	_build_about_page()

	# ---- 二次确认条 ----
	_confirm_bar = PanelContainer.new()
	_confirm_bar.visible = false
	var csb := StyleBoxFlat.new()
	csb.bg_color = Color(0.25, 0.12, 0.10, 0.98)
	csb.border_color = Color(1.0, 0.6, 0.4, 0.9)
	csb.set_border_width_all(1)
	csb.content_margin_left = 4
	csb.content_margin_right = 4
	csb.content_margin_top = 3
	csb.content_margin_bottom = 3
	_confirm_bar.add_theme_stylebox_override("panel", csb)
	_col.add_child(_confirm_bar)

	var crow := HBoxContainer.new()
	crow.add_theme_constant_override("separation", 4)
	_confirm_bar.add_child(crow)

	_confirm_label = Label.new()
	_confirm_label.text = ""
	_confirm_label.add_theme_font_size_override("font_size", F_SMALL)
	_confirm_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_confirm_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	crow.add_child(_confirm_label)

	var yes := Button.new()
	yes.text = "确认"
	yes.add_theme_font_size_override("font_size", F_SMALL)
	yes.pressed.connect(_on_confirm)
	crow.add_child(yes)

	var no := Button.new()
	no.text = "取消"
	no.add_theme_font_size_override("font_size", F_SMALL)
	no.pressed.connect(_hide_confirm)
	crow.add_child(no)


# ============================================================ 控件工厂

func _new_page(key: String) -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.name = "Page_" + key
	margin.visible = false
	_pages_holder.add_child(margin)

	var page := VBoxContainer.new()
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 3)
	margin.add_child(page)

	_pages[key] = margin
	return page


func _label(parent: Node, text: String, size: int = F_BODY, alpha: float = 1.0) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	if alpha < 1.0:
		l.modulate = Color(1, 1, 1, alpha)
	parent.add_child(l)
	return l


func _slider_row(parent: Node, key: String, title: String, minv: float, maxv: float, step: float, presets: Array) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	parent.add_child(row)

	var name_label := Label.new()
	name_label.text = title
	name_label.custom_minimum_size = Vector2(42, 0)
	name_label.add_theme_font_size_override("font_size", F_BODY)
	row.add_child(name_label)

	var slider := HSlider.new()
	slider.min_value = minv
	slider.max_value = maxv
	slider.step = step
	slider.value = 1.0
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)

	var value_label := Label.new()
	value_label.text = "1.0x"
	value_label.custom_minimum_size = Vector2(30, 0)
	value_label.add_theme_font_size_override("font_size", F_SMALL)
	row.add_child(value_label)

	slider.value_changed.connect(func(v: float) -> void:
		value_label.text = "%.1fx" % v
		if _syncing:
			return
		_on_slider_changed(key, v)
	)

	if not presets.is_empty():
		var pr := HBoxContainer.new()
		pr.add_theme_constant_override("separation", 1)
		row.add_child(pr)
		for p in presets:
			var b := Button.new()
			b.text = str(p)
			b.add_theme_font_size_override("font_size", F_SMALL)
			b.pressed.connect(func() -> void:
				slider.value = float(p)
			)
			pr.add_child(b)

	_sliders[key] = {"slider": slider, "label": value_label}


func _check_row(parent: Node, key: String, title: String, on_change: Callable) -> CheckButton:
	var c := CheckButton.new()
	c.text = title
	c.add_theme_font_size_override("font_size", F_BODY)
	c.toggled.connect(func(v: bool) -> void:
		if _syncing:
			return
		on_change.call(v)
	)
	parent.add_child(c)
	_checks[key] = c
	return c


func _row(parent: Node) -> HBoxContainer:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 4)
	parent.add_child(r)
	return r


func _hsep(parent: Node) -> void:
	parent.add_child(HSeparator.new())


# ============================================================ 各页

func _build_stats_page() -> void:
	var p := _new_page("stats")
	_label(p, "预设", F_SMALL, 0.7)
	var pr := _row(p)
	for item in [["轻度", "light"], ["爽玩", "fun"], ["全开", "all"]]:
		var b := Button.new()
		b.text = str(item[0])
		b.add_theme_font_size_override("font_size", F_SMALL)
		b.pressed.connect(_apply_preset.bind(str(item[1])))
		pr.add_child(b)

	_hsep(p)
	_label(p, "倍率：关闭即还原，保留本局自然成长", F_SMALL, 0.7)
	_slider_row(p, "speed", "移速", 0.1, 10.0, 0.1, [1, 2, 5, 10])
	_slider_row(p, "fire", "射速", 0.1, 10.0, 0.1, [1, 2, 5, 10])
	_slider_row(p, "damage", "伤害", 0.1, 10.0, 0.1, [1, 2, 5, 10])
	_slider_row(p, "pickup", "拾取", 0.1, 10.0, 0.1, [1, 2, 5, 10])

	_hsep(p)
	_check_row(p, "invincible", "无敌（不受伤）", func(v: bool) -> void: core.set_invincible(v))
	_check_row(p, "one_hit_kill", "秒杀（一击致命）", func(v: bool) -> void: core.set_one_hit_kill(v))


func _build_resource_page() -> void:
	var p := _new_page("res")
	_label(p, "金币（局内货币，不写入存档）", F_SMALL, 0.75)
	var r1 := _row(p)
	for item in [["+1000", 1000], ["+10000", 10000], ["-1000", -1000]]:
		var b := Button.new()
		b.text = str(item[0])
		b.add_theme_font_size_override("font_size", F_SMALL)
		b.pressed.connect(core.add_coin.bind(int(item[1])))
		r1.add_child(b)

	var r2 := _row(p)
	var coin_edit := LineEdit.new()
	coin_edit.placeholder_text = "数量"
	coin_edit.custom_minimum_size = Vector2(70, 0)
	coin_edit.add_theme_font_size_override("font_size", F_SMALL)
	r2.add_child(coin_edit)
	var set_coin := Button.new()
	set_coin.text = "增加"
	set_coin.add_theme_font_size_override("font_size", F_SMALL)
	set_coin.pressed.connect(func() -> void: core.add_coin(int(coin_edit.text)))
	r2.add_child(set_coin)

	_hsep(p)
	_label(p, "青辉石（元货币，会立即写入存档）", F_SMALL, 0.75)
	var r3 := _row(p)
	for item in [["+100", 100], ["+1000", 1000], ["+9999", 9999]]:
		var b := Button.new()
		b.text = str(item[0])
		b.add_theme_font_size_override("font_size", F_SMALL)
		b.pressed.connect(_ask_confirm.bind(
			"该操作会修改存档（青辉石 +%d），继续？" % int(item[1]),
			core.add_pyroxenes.bind(int(item[1]))))
		r3.add_child(b)


func _build_unlock_page() -> void:
	var p := _new_page("unlock")
	_label(p, "解锁范围：角色 / 服装 / 支援（游戏模式是玩法开关，不算解锁项）", F_SMALL, 0.75)
	_label(p, "该操作会写入存档且不可撤销。", F_SMALL, 0.75)
	var b := Button.new()
	b.text = "一键全部解锁"
	b.add_theme_font_size_override("font_size", F_BODY)
	b.custom_minimum_size = Vector2(0, 24)
	b.pressed.connect(_ask_confirm.bind(
		"该操作会修改存档（角色 / 服装 / 支援全部解锁），继续？", core.unlock_all))
	p.add_child(b)
	_hsep(p)
	_label(p, "解锁后若界面没刷新，回主菜单再进一次即可。", F_SMALL, 0.55)


func _build_support_page() -> void:
	var p := _new_page("support")
	_label(p, "额外减伤上限：叠加在角色原护甲上限上", F_SMALL, 0.75)
	_slider_row(p, "reduce", "减伤", 0.0, 0.75, 0.05, [])
	_sliders["reduce"]["label"].text = "+0%"
	_label(p, "护甲值：在自然护甲之上加算（与减伤上限搭配生效）", F_SMALL, 0.75)
	_slider_row(p, "armor", "护甲", 0.0, 100.0, 5.0, [0, 20, 50, 100])
	_sliders["armor"]["label"].text = "+0"
	_hsep(p)
	var heal := Button.new()
	heal.text = "回满血"
	heal.add_theme_font_size_override("font_size", F_BODY)
	heal.custom_minimum_size = Vector2(0, 24)
	heal.pressed.connect(func() -> void: core.heal_full())
	p.add_child(heal)


func _build_debug_page() -> void:
	var p := _new_page("debug")
	var r1 := _row(p)
	var clear := Button.new()
	clear.text = "清屏"
	clear.add_theme_font_size_override("font_size", F_SMALL)
	clear.pressed.connect(func() -> void: core.clear_enemies())
	r1.add_child(clear)

	var endr := Button.new()
	endr.text = "结束本回合"
	endr.add_theme_font_size_override("font_size", F_SMALL)
	endr.pressed.connect(func() -> void: core.end_round())
	r1.add_child(endr)

	_hsep(p)
	_label(p, "生成敌人", F_SMALL, 0.75)
	var r2 := _row(p)
	_enemy_option = OptionButton.new()
	_enemy_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_enemy_option.add_theme_font_size_override("font_size", F_SMALL)
	r2.add_child(_enemy_option)
	var spawn := Button.new()
	spawn.text = "生成"
	spawn.add_theme_font_size_override("font_size", F_SMALL)
	spawn.pressed.connect(_on_spawn_pressed)
	r2.add_child(spawn)

	_hsep(p)
	_status = _label(p, "状态：-", F_SMALL, 0.85)
	_countdown_label = _label(p, "倒计时：-", F_SMALL, 0.55)


func _build_about_page() -> void:
	var p := _new_page("about")
	_label(p, "etn_trainer 0.1.0", F_BODY)
	_label(p, "F1 开关面板；局内打开会自动暂停。", F_SMALL, 0.8)
	_label(p, "F2 是本体内置作弊菜单（需 config.ini 开启 developer_mode），两者互不影响。", F_SMALL, 0.8)
	_label(p, "作弊倍率每局归零，不写存档；面板位置与 HUD 开关会记住。", F_SMALL, 0.8)
	_hsep(p)
	_check_row(p, "dev_mode", "启用本体开发者模式（只改内存，不写 config.ini）",
		func(v: bool) -> void: core.set_dev_mode(v))
	_check_row(p, "hud", "显示常驻 HUD（FPS / 敌人数 / 回合）",
		func(v: bool) -> void:
			core.hud_on = v
			core.save_prefs()
			if hud != null:
				hud.set_shown(v))
	_hsep(p)
	var reset := Button.new()
	reset.text = "全部重置（关闭所有作弊）"
	reset.add_theme_font_size_override("font_size", F_SMALL)
	reset.custom_minimum_size = Vector2(0, 24)
	reset.pressed.connect(_reset_all)
	p.add_child(reset)


# ============================================================ 交互

func _on_slider_changed(key: String, v: float) -> void:
	match key:
		"speed":
			core.speed_mult = v
		"fire":
			core.fire_rate_mult = v
		"damage":
			core.damage_mult = v
		"pickup":
			core.pickup_mult = v
		"reduce":
			core.armor_cap = v
			_sliders["reduce"]["label"].text = "+%d%%" % int(round(v * 100.0))
		"armor":
			core.armor_add = v
			_sliders["armor"]["label"].text = "+%d" % int(round(v))
	core.push_values()


func _apply_preset(kind: String) -> void:
	match kind:
		"light":
			core.speed_mult = 1.2
			core.fire_rate_mult = 1.2
			core.damage_mult = 1.5
			core.pickup_mult = 2.0
			core.set_invincible(false)
			core.set_one_hit_kill(false)
		"fun":
			core.speed_mult = 1.5
			core.fire_rate_mult = 2.0
			core.damage_mult = 5.0
			core.pickup_mult = 3.0
			core.set_invincible(true)
			core.set_one_hit_kill(false)
		"all":
			core.speed_mult = 2.0
			core.fire_rate_mult = 5.0
			core.damage_mult = 10.0
			core.pickup_mult = 5.0
			core.armor_cap = 0.65
			core.armor_add = 60.0
			core.set_invincible(true)
			core.set_one_hit_kill(true)
	core.push_values()
	_sync_from_core()
	show_notice("已应用预设：" + str(kind))


func _reset_all() -> void:
	core.speed_mult = 1.0
	core.fire_rate_mult = 1.0
	core.damage_mult = 1.0
	core.pickup_mult = 1.0
	core.armor_cap = -1.0
	core.armor_add = 0.0
	core.set_invincible(false)
	core.set_one_hit_kill(false)
	core.push_values()
	_sync_from_core()
	show_notice("已全部重置")


func _on_spawn_pressed() -> void:
	if _enemy_option == null:
		return
	var idx: int = _enemy_option.selected
	if idx < 0 or idx >= _enemy_cards.size():
		return
	core.spawn_enemy(_enemy_cards[idx])


func _ask_confirm(text: String, cb: Callable) -> void:
	_confirm_cb = cb
	_confirm_label.text = text
	_confirm_bar.visible = true


func _hide_confirm() -> void:
	_confirm_bar.visible = false
	_confirm_cb = Callable()


func _on_confirm() -> void:
	var cb := _confirm_cb
	_hide_confirm()
	if cb.is_valid():
		cb.call()


func show_notice(text: String) -> void:
	if _toast == null:
		return
	_toast.text = text
	_toast.visible = true
	_toast_left = 3.0


# ============================================================ 状态同步

func _show_tab(key: String) -> void:
	_current_tab = key
	for k in _pages.keys():
		_pages[k].visible = (str(k) == key)
	for k in _tab_buttons.keys():
		var b: Button = _tab_buttons[k]
		b.modulate = Color(1, 1, 1, 1.0) if str(k) == key else Color(1, 1, 1, 0.62)
	if key == "debug":
		_refresh_enemy_list()


func _refresh_enemy_list() -> void:
	if _enemy_option == null:
		return
	_enemy_cards = core.list_enemy_cards()
	_enemy_option.clear()
	for card in _enemy_cards:
		_enemy_option.add_item(str(card.get("id")))
	if _enemy_cards.is_empty():
		_enemy_option.add_item("（无可用敌人）")


func _sync_from_core() -> void:
	_syncing = true
	var vals := {
		"speed": core.speed_mult,
		"fire": core.fire_rate_mult,
		"damage": core.damage_mult,
		"pickup": core.pickup_mult,
		"reduce": maxf(0.0, core.armor_cap),
		"armor": core.armor_add,
	}
	for k in vals.keys():
		if not _sliders.has(k):
			continue
		var s: HSlider = _sliders[k]["slider"]
		s.value = float(vals[k])
		if k == "reduce":
			_sliders[k]["label"].text = "+%d%%" % int(round(float(vals[k]) * 100.0))
		elif k == "armor":
			_sliders[k]["label"].text = "+%d" % int(round(float(vals[k])))
		else:
			_sliders[k]["label"].text = "%.1fx" % float(vals[k])
	_checks["invincible"].button_pressed = core.invincible
	_checks["one_hit_kill"].button_pressed = core.one_hit_kill
	_checks["hud"].button_pressed = core.hud_on
	_checks["dev_mode"].button_pressed = core.dev_mode_on
	_checks["dev_mode"].disabled = core.dev_mode_locked
	if core.dev_mode_locked:
		_checks["dev_mode"].text = "开发者模式（config.ini 已启用，锁定）"
	_syncing = false


func _process(delta: float) -> void:
	if not visible:
		return
	if _toast_left > 0.0:
		_toast_left -= delta
		if _toast_left <= 0.0 and _toast != null:
			_toast.visible = false
	_tick += delta
	if _tick < 0.25:
		return
	_tick = 0.0
	if _current_tab == "debug":
		_refresh_status()


func _refresh_status() -> void:
	if _status == null or core == null:
		return
	var count: int = PoolManager.get_active_enemies().size()
	var rt = core.get_round_timer()
	var rnd: int = 0
	var left: float = 0.0
	if rt != null:
		rnd = int(rt.get("now_round_num"))
		if rt.get("timer") != null:
			left = float(rt.timer.time_left)
	_status.text = "状态：在场敌人 %d ｜ 玩家 %s" % [count, "在" if core.in_game() else "无"]
	_countdown_label.text = "第 %d 回合 ｜ 倒计时 %.1fs" % [rnd, left]


# ============================================================ 开关面板

func toggle() -> void:
	if visible:
		close_panel()
	else:
		open_panel()


func open_panel() -> void:
	if visible:
		return
	# 关键：本体 GUI 命中测试按场景树逆序（不是按 CanvasLayer.layer）走，
	# 切场景后新场景是 root 的最后一个子节点，会把挂在 root 下的本面板挡在下面。
	# 打开时把面板移到 root 末尾，保证它排在当前场景之后、优先收到鼠标事件。
	var root := get_tree().root
	if get_parent() == root:
		root.move_child(self, root.get_child_count() - 1)
	if hud != null and hud.get_parent() == root:
		root.move_child(hud, root.get_child_count() - 1)
	_layout()
	_sync_from_core()
	_apply_lock_state()
	_show_tab(_current_tab)
	visible = true
	_prev_mouse = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_external_lock = false
	if not GameEvents.pause_lock.is_connected(_on_pause_lock):
		GameEvents.pause_lock.connect(_on_pause_lock)
	if core.in_game():
		var t := get_tree()
		if t != null and not t.paused:
			_paused_by_us = true
			_self_lock = true
			GameEvents.emit_pause_lock(true)
			_self_lock = false
			t.paused = true


func close_panel() -> void:
	if not visible:
		return
	visible = false
	_hide_confirm()
	Input.mouse_mode = _prev_mouse
	if GameEvents.pause_lock.is_connected(_on_pause_lock):
		GameEvents.pause_lock.disconnect(_on_pause_lock)
	# 若期间回合结束/升级页等系统也上了暂停锁，就把暂停交还给它们
	if _paused_by_us and not _external_lock:
		_paused_by_us = false
		var t := get_tree()
		if t != null:
			t.paused = false
			_self_lock = true
			GameEvents.emit_pause_lock(false)
			_self_lock = false
	else:
		_paused_by_us = false
	core.panel_pos = _panel.position
	core.save_prefs()


## 按 640x360 基准视口显式计算面板矩形，避免超出视口或依赖容器的隐式撑开。
func _layout() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var pw: float = minf(600.0, maxf(360.0, vp.x - 32.0))
	var ph: float = minf(336.0, maxf(240.0, vp.y - 24.0))
	_panel.size = Vector2(pw, ph)
	_dim.size = vp
	if core.panel_pos.x < -90000.0:
		_panel.position = ((vp - _panel.size) * 0.5).floor()
	else:
		_panel.position = Vector2(
			clampf(core.panel_pos.x, 0.0, maxf(0.0, vp.x - pw)),
			clampf(core.panel_pos.y, 0.0, maxf(0.0, vp.y - ph)))
	_col.queue_sort()


func _apply_lock_state() -> void:
	var locked: bool = core.is_locked()
	if locked:
		_banner.visible = true
		_banner.text = "联机会话中：修改器已禁用（防止污染他人房间）。"
		_body.modulate = Color(1, 1, 1, 0.45)
		_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	else:
		if not core.in_game():
			_banner.visible = true
			_banner.text = "当前不在对局中：数值 / 辅助 / 调试 页不可用。"
			_banner.add_theme_color_override("font_color", Color(0.8, 0.85, 1.0))
		else:
			_banner.visible = false
		_body.modulate = Color(1, 1, 1, 1.0)
		_body.mouse_filter = Control.MOUSE_FILTER_STOP


func _on_pause_lock(locked: bool) -> void:
	if _self_lock:
		return
	_external_lock = locked


func _on_header_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_dragging = true
				_drag_off = get_viewport().get_mouse_position() - _panel.position
			else:
				_dragging = false
				core.panel_pos = _panel.position
				core.save_prefs()
	elif event is InputEventMouseMotion and _dragging:
		var target: Vector2 = get_viewport().get_mouse_position() - _drag_off
		var vp: Vector2 = get_viewport().get_visible_rect().size
		_panel.position = Vector2(
			clampf(target.x, -_panel.size.x + 40.0, vp.x - 40.0),
			clampf(target.y, 0.0, vp.y - 20.0))


## 面板本体吃掉点击，避免穿透到游戏
func _on_panel_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close_panel()
		get_viewport().set_input_as_handled()
