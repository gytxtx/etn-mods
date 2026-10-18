extends Node

## etn_trainer 入口：注册 F1、挂面板与 HUD、把 core 的提示转发到面板。

const CoreScript := preload("res://mods/etn_trainer/core/trainer_core.gd")
const PanelScript := preload("res://mods/etn_trainer/ui/trainer_panel.gd")
const HudScript := preload("res://mods/etn_trainer/ui/trainer_hud.gd")

const ACTION := "trainer_toggle"

var core: Node = null
var panel: CanvasLayer = null
var hud: CanvasLayer = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_register_action()

	core = CoreScript.new()
	core.name = "TrainerCore"
	add_child(core)
	core.setup()

	panel = PanelScript.new()
	panel.name = "TrainerPanel"
	panel.core = core

	hud = HudScript.new()
	hud.name = "TrainerHud"
	hud.core = core

	var root := get_tree().root
	root.add_child(panel)
	root.add_child(hud)
	panel.hud = hud
	hud.set_shown(core.hud_on)

	core.notice.connect(_on_notice)
	print_rich("[etn_trainer] entry ready (ModAPI v%d, 面板 %s)" % [
		ModAPI.VERSION,
		"已挂载" if panel.is_inside_tree() else "挂载失败",
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
	print_rich("[etn_trainer] selftest: begin (in_game=%s)" % str(core.in_game()))
	panel.open_panel()
	print_rich("[etn_trainer] selftest: panel visible=%s, paused=%s, locked=%s" % [
		str(panel.visible), str(get_tree().paused), str(core.is_locked()),
	])
	for tab in ["stats", "res", "unlock", "support", "debug", "about"]:
		panel._show_tab(tab)
		print_rich("[etn_trainer] selftest: tab %s ok" % tab)
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
	print_rich("[etn_trainer] selftest: paused after close=%s (期望 true，锁交还)" % str(get_tree().paused))
	get_tree().quit()


func _on_notice(text: String) -> void:
	print_rich("[etn_trainer] ", text)
	if panel != null and panel.has_method("show_notice"):
		panel.show_notice(text)
