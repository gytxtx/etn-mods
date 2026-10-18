extends Button

## 项目关闭触屏模拟鼠标，按钮须在同指有效释放时激活，拖动时交给滚动区。
var _finger := -1
var _origin := Vector2.ZERO
var _dragged := false

func _ready() -> void:
	install_touch()

func install_touch() -> void:
	if not gui_input.is_connected(_touch_input):
		gui_input.connect(_touch_input)
	mouse_filter = Control.MOUSE_FILTER_PASS
	if OS.has_feature("mobile"):
		var scale_y := get_viewport().get_screen_transform().get_scale().y
		var dpi := maxf(DisplayServer.screen_get_dpi(), 160)
		var target := 48.0 * dpi / 160.0 / maxf(scale_y, 0.01)
		custom_minimum_size.x = maxf(custom_minimum_size.x, target)
		custom_minimum_size.y = maxf(custom_minimum_size.y, target)

func _input(event: InputEvent) -> void:
	if _finger < 0:
		return
	if event is InputEventScreenDrag and event.index == _finger:
		if event.position.distance_to(_origin) > 8:
			_dragged = true
	if event is InputEventScreenTouch and event.index == _finger and not event.pressed:
		_clear_touch.call_deferred()

func _touch_input(event: InputEvent) -> void:
	if disabled or mouse_filter == Control.MOUSE_FILTER_IGNORE:
		return
	if event is InputEventScreenTouch:
		if event.pressed and _finger < 0:
			_finger = event.index
			_origin = get_global_transform_with_canvas() * event.position
			_dragged = false
		elif not event.pressed and event.index == _finger:
			var valid: bool = not event.canceled and not _dragged and Rect2(Vector2.ZERO, size).has_point(event.position)
			_clear_touch()
			if valid:
				grab_focus()
				if toggle_mode:
					button_pressed = not button_pressed
				pressed.emit()
			accept_event()

func _clear_touch() -> void:
	_finger = -1
	_dragged = false
