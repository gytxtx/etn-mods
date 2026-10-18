extends ScrollContainer

## 整个 EasyTier 表单共用一个滚动区，滚动容器和滚动条也需登记交互白名单。
func get_interactive_controls() -> Array[Control]:
	var controls: Array[Control] = [self, get_v_scroll_bar()]
	controls.append_array($Form.get_interactive_controls())
	return controls
