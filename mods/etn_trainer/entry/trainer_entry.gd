extends Node

## etn_trainer 入口：注册 F1、挂面板与 HUD、把 core 的提示转发到面板。
## 移动端没有 F1：由 HUD 行的常驻「修改器」按钮打开面板（hud.open_requested）。

const CoreScript := preload("res://mods/etn_trainer/core/trainer_core.gd")
const PanelScript := preload("res://mods/etn_trainer/ui/trainer_panel.gd")
const HudScript := preload("res://mods/etn_trainer/ui/trainer_hud.gd")
const TouchScrollScript := preload("res://mods/etn_trainer/ui/touch_scroll.gd")

const ACTION := "trainer_toggle"

var core: Node = null
var panel: CanvasLayer = null
var hud: CanvasLayer = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_register_action()

	# 桌面测试移动端布局用 --trainer-mobile 强制；真机走 OS.has_feature("mobile")。
	var mobile: bool = OS.has_feature("mobile") or "--trainer-mobile" in OS.get_cmdline_user_args()

	core = CoreScript.new()
	core.name = "TrainerCore"
	add_child(core)
	core.setup()

	panel = PanelScript.new()
	panel.name = "TrainerPanel"
	panel.core = core
	panel.mobile = mobile

	hud = HudScript.new()
	hud.name = "TrainerHud"
	hud.core = core
	hud.mobile = mobile

	var root := get_tree().root
	root.add_child(panel)
	root.add_child(hud)
	panel.hud = hud
	hud.open_requested.connect(panel.toggle)
	hud.set_shown(core.hud_on)

	core.notice.connect(_on_notice)
	print_rich("[etn_trainer] entry ready (ModAPI v%d, 面板 %s, 移动端 %s)" % [
		ModAPI.VERSION,
		"已挂载" if panel.is_inside_tree() else "挂载失败",
		"是" if mobile else "否",
	])
	if "--trainer-selftest" in OS.get_cmdline_user_args():
		_run_selftest.call_deferred()


func _register_action() -> void:
	if InputMap.has_action(ACTION):
		return
	InputMap.add_action(ACTION)
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_F1
	InputMap.action_add_event(ACTION, ev)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(ACTION):
		return
	if panel == null:
		return
	panel.toggle()
	get_viewport().set_input_as_handled()


## 无头自检：--trainer-selftest 启动时逐个页签展开并调用主要接口，验证面板与数值注入无误。
## 移动端 / 触屏：追加 --trainer-mobile，会强制移动端布局并注入合成触摸事件。
func _run_selftest() -> void:
	for i in 12:
		await get_tree().process_frame
	# --trainer-scene=res://... 先把场景切过去，用于在无头模式下验证"局内"路径
	var target := ""
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with("--trainer-scene="):
			target = str(a).substr("--trainer-scene=".length())
	if target != "":
		print_rich("[etn_trainer] selftest: switching scene -> %s" % target)
		# 走本体的切场景链路，玩家才会被实例化进 PlayerRoot（直接 change_scene_to_file 不会）
		GameEvents.change_scene(target, "res://scenes/player/momoi/momoi.tscn")
		await get_tree().create_timer(1.5).timeout
		for i in 10:
			await get_tree().process_frame
	var cs := get_tree().current_scene
	print_rich("[etn_trainer] selftest: scene=%s" % (cs.scene_file_path if cs != null else "<none>"))
	print_rich("[etn_trainer] selftest: begin (in_game=%s, mobile=%s)" % [
		str(core.in_game()), str(panel.mobile),
	])
	var shots: bool = "--trainer-shots" in OS.get_cmdline_user_args()
	if shots:
		await _save_shot("ingame_hud")

	var failures := 0
	# 移动端入口按钮：面板关闭时应可见，点按后打开面板。
	if panel.mobile:
		failures += await _check_hud_button()
		await get_tree().process_frame

	panel.open_panel()
	print_rich("[etn_trainer] selftest: panel visible=%s, paused=%s, locked=%s" % [
		str(panel.visible), str(get_tree().paused), str(core.is_locked()),
	])
	for tab in ["stats", "res", "unlock", "support", "debug", "about"]:
		panel._show_tab(tab)
		print_rich("[etn_trainer] selftest: tab %s ok" % tab)
		if shots:
			await get_tree().process_frame
			await _save_shot("panel_" + tab)

	if panel.mobile:
		panel._show_tab("stats")
		for i in 3:
			await get_tree().process_frame
		# 非对局时数值页是「需要在对局中」遮罩，滑条不可见/不可点。
		if core.in_game():
			failures += await _check_touch_slider()
		failures += await _check_touch_drag()
		failures += await _check_touch_scroll()
		if core.in_game():
			failures += await _check_touch_page_scroll()
			failures += await _check_touch_button()
		if core.in_game():
			failures += await _check_touch_edit()

	var enemies: Array = core.list_enemy_cards()
	print_rich("[etn_trainer] selftest: enemy cards=%d" % enemies.size())

	var p = core.get_player()
	if p != null:
		var s = p.get("stats")
		print_rich("[etn_trainer] selftest: before speed=%s rpm=%s dmg=%s range=%s" % [
			str(s.MAX_SPEED), str(s.bullet_shoot_time), str(s.global_damage), str(s.pick_up_range),
		])
		core.speed_mult = 2.0
		core.fire_rate_mult = 2.0
		core.damage_mult = 3.0
		core.pickup_mult = 4.0
		core.armor_add = 50.0
		core.armor_cap = 0.1
		core.push_values()
		print_rich("[etn_trainer] selftest: after  speed=%s rpm=%s dmg=%s range=%s resis=%s cap=%s" % [
			str(s.MAX_SPEED), str(s.bullet_shoot_time), str(s.global_damage), str(s.pick_up_range),
			str(s.hurt_resis), str(p.health_component.armor_cap),
		])
		core.heal_full()
		core.set_invincible(true)
		print_rich("[etn_trainer] selftest: invincible=%s hp=%s/%s" % [
			str(p.health_component.is_invincible), str(s.hp), str(s.max_hp),
		])
		core.set_invincible(false)
		print_rich("[etn_trainer] selftest: clear enemies killed=%d" % core.clear_enemies())
		if not enemies.is_empty():
			core.spawn_enemy(enemies[0])
		core.add_coin(500)
		print_rich("[etn_trainer] selftest: coin=%s" % str(s.coin))
	else:
		core.add_coin(1)
	# 模拟"面板打开期间别的系统也上了暂停锁"（如回合结束/升级页），验证关面板不会把它的锁打掉
	GameEvents.emit_pause_lock(true)
	print_rich("[etn_trainer] selftest: paused before close=%s" % str(get_tree().paused))
	panel.close_panel()
	print_rich("[etn_trainer] selftest: paused after close=%s (对局内期望 true，锁交还)" % str(get_tree().paused))
	print_rich("[etn_trainer] selftest: touch failures=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _save_shot(shot_name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var dir := "user://trainer_shots"
	DirAccess.make_dir_recursive_absolute(dir)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img != null:
		img.save_png(dir.path_join(shot_name + ".png"))


func _check(name: String, ok: bool) -> int:
	print_rich("[etn_trainer] selftest: %s %s" % ["PASS" if ok else "FAIL", name])
	return 0 if ok else 1


func _touch(index: int, pressed: bool, pos: Vector2) -> InputEventScreenTouch:
	var ev := InputEventScreenTouch.new()
	ev.index = index
	ev.pressed = pressed
	ev.position = pos
	return ev


func _drag(index: int, pos: Vector2) -> InputEventScreenDrag:
	var ev := InputEventScreenDrag.new()
	ev.index = index
	ev.position = pos
	return ev


func _push(event: InputEvent) -> void:
	get_viewport().push_input(event, true)


func _check_hud_button() -> int:
	var fail := 0
	var btn: Button = hud._open_button
	fail += _check("移动端 HUD 入口按钮存在", btn != null and is_instance_valid(btn))
	if btn == null:
		return fail
	fail += _check("入口按钮可见", btn.visible and hud.visible)
	var rect: Rect2 = btn.get_global_rect()
	var point := rect.position + rect.size * 0.5
	_push(_touch(6, true, point))
	_push(_touch(6, false, point))
	for i in 2:
		await get_tree().process_frame
	fail += _check("触屏点按入口按钮打开面板", panel.visible)
	fail += _check("面板打开时入口按钮隐藏", not btn.visible)
	panel.close_panel()
	await get_tree().process_frame
	return fail


func _check_touch_slider() -> int:
	var slider: HSlider = panel._sliders["speed"]["slider"]
	var rect: Rect2 = slider.get_global_rect()
	var y := rect.position.y + rect.size.y * 0.5
	var p25 := Vector2(rect.position.x + rect.size.x * 0.25, y)
	var p75 := Vector2(rect.position.x + rect.size.x * 0.75, y)
	var page_scroll = panel._pages["stats"]
	var scroll_before: int = page_scroll.scroll_vertical
	_push(_touch(7, true, p25))
	for i in 2:
		await get_tree().process_frame
	var v25: float = core.speed_mult
	_push(_drag(7, p75))
	for i in 2:
		await get_tree().process_frame
	var v75: float = core.speed_mult
	_push(_touch(7, false, p75))
	for i in 2:
		await get_tree().process_frame
	var ok: bool = absf(v25 - 2.6) < 0.2 and absf(v75 - 7.5) < 0.06
	_check("触屏点按 25%% → %.1fx、拖到 75%% → %.1fx" % [v25, v75], ok)
	var ok_scroll: bool = page_scroll.scroll_vertical == scroll_before
	_check("拖滑条不带动页面滚动（%d → %d）" % [scroll_before, page_scroll.scroll_vertical], ok_scroll)
	core.speed_mult = 1.0
	core.push_values()
	panel._sync_from_core()
	return 0 if ok and ok_scroll else 1


func _check_touch_drag() -> int:
	var before: Vector2 = panel._panel.position
	var hrect: Rect2 = panel._header.get_global_rect()
	var start := hrect.position + Vector2(hrect.size.x * 0.2, hrect.size.y * 0.5)
	_push(_touch(8, true, start))
	_push(_drag(8, start + Vector2(0, 12)))
	_push(_touch(8, false, start + Vector2(0, 12)))
	for i in 2:
		await get_tree().process_frame
	var moved: float = panel._panel.position.y - before.y
	var ok: bool = absf(moved - 12.0) < 1.5
	_check("触屏拖动标题栏（位移 %.1fpx）" % moved, ok)
	panel._recenter()
	return 0 if ok else 1


func _check_touch_edit() -> int:
	panel._show_tab("debug")
	for i in 3:
		await get_tree().process_frame
	var edit: LineEdit = panel._enemy_search
	edit.release_focus()
	var rect: Rect2 = edit.get_global_rect()
	var point := rect.position + rect.size * 0.5
	_push(_touch(11, true, point))
	_push(_touch(11, false, point))
	for i in 2:
		await get_tree().process_frame
	var ok: bool = edit.has_focus()
	_check("触屏点按输入框获得焦点", ok)
	edit.release_focus()
	return 0 if ok else 1


## 复选框走 4.7 BaseButton 原生 ScreenTouch；触屏点按应切换并同步 core。
func _check_touch_button() -> int:
	panel._show_tab("stats")
	for i in 2:
		await get_tree().process_frame
	var check: CheckBox = panel._checks["invincible"]
	check.button_pressed = false
	var rect: Rect2 = check.get_global_rect()
	var point := rect.position + rect.size * 0.5
	_push(_touch(13, true, point))
	_push(_touch(13, false, point))
	for i in 2:
		await get_tree().process_frame
	var on: bool = check.button_pressed and core.invincible
	_push(_touch(14, true, point))
	_push(_touch(14, false, point))
	for i in 2:
		await get_tree().process_frame
	var off: bool = not check.button_pressed and not core.invincible
	_check("触屏点按复选框开/关（%s / %s）" % [str(on), str(off)], on and off)
	return 0 if on and off else 1


## 真实页面：在滑条行右侧空白处按下并上拖，验证每页的 TouchScroll 确实接管手势。
func _check_touch_page_scroll() -> int:
	panel._show_tab("stats")
	for i in 2:
		await get_tree().process_frame
	var page = panel._pages["stats"]
	var rect: Rect2 = page.get_global_rect()
	# 页面顶部标题行：文字已设 IGNORE，触摸应穿透到页面滚动区。
	var start := Vector2(rect.position.x + rect.size.x * 0.5, rect.position.y + 10.0)
	var before: int = page.scroll_vertical
	_push(_touch(12, true, start))
	_push(_drag(12, start - Vector2(0, 40)))
	_push(_touch(12, false, start - Vector2(0, 40)))
	for i in 2:
		await get_tree().process_frame
	var ok: bool = page.scroll_vertical > before
	_check("触屏拖动页面滚动（%d → %d）" % [before, page.scroll_vertical], ok)
	page.scroll_vertical = before
	return 0 if ok else 1


func _check_touch_scroll() -> int:
	var scroll = TouchScrollScript.new()
	scroll.position = Vector2(4, 150)
	scroll.size = Vector2(220, 100)
	# 挂在面板 CanvasLayer 内、晚于遮罩加入 → 命中测试位于最上层。
	panel.add_child(scroll)
	var content := Control.new()
	content.mouse_filter = Control.MOUSE_FILTER_PASS
	content.custom_minimum_size = Vector2(200, 420)
	scroll.add_child(content)
	for i in 2:
		await get_tree().process_frame
	var start := Vector2(100, 190)
	_push(_touch(9, true, start))
	_push(_drag(9, start - Vector2(0, 40)))
	_push(_touch(9, false, start - Vector2(0, 40)))
	await get_tree().process_frame
	var ok: bool = scroll.scroll_vertical >= 30
	_check("触屏拖动滚动容器（scroll=%d）" % scroll.scroll_vertical, ok)
	scroll.queue_free()
	return 0 if ok else 1


func _on_notice(text: String) -> void:
	print_rich("[etn_trainer] ", text)
	if panel != null and panel.has_method("show_notice"):
		panel.show_notice(text)
