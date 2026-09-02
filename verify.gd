extends SceneTree

const UI_PATH := "res://addons/gmorn_ui/gmorn_ui.gd"
const FOCUS_THEME_PATH := "res://addons/gmorn_ui/button_focus_theme.tres"

var _checked := 0
var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(640, 360)
	var service: Node = load(UI_PATH).new()
	root.add_child(service)

	var screen := VBoxContainer.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(screen)
	var first := Button.new()
	first.text = "先頭"
	var first_normal := StyleBoxFlat.new()
	first_normal.bg_color = Color(0.08, 0.07, 0.1, 1.0)
	first_normal.set_corner_radius_all(17)
	first.add_theme_stylebox_override("normal", first_normal)
	var first_hover := StyleBoxFlat.new()
	first_hover.bg_color = Color(0.2, 0.3, 0.4, 1.0)
	first.add_theme_stylebox_override("hover", first_hover)
	var second := Button.new()
	second.text = "次"
	second.mouse_behavior_recursive = Control.MOUSE_BEHAVIOR_ENABLED
	second.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_ENABLED
	screen.add_child(first)
	screen.add_child(second)
	var intentional_focus := StyleBoxFlat.new()
	intentional_focus.bg_color = Color(0.4, 0.3, 0.2, 1.0)
	var intentional_focus_color := Color(0.7, 0.9, 1.0, 1.0)
	second.add_theme_stylebox_override("focus", intentional_focus)
	second.add_theme_color_override("font_focus_color", intentional_focus_color)
	var focus_theme := load(FOCUS_THEME_PATH) as Theme
	var focus_template := focus_theme.get_stylebox("focus", "Button") as StyleBoxFlat
	var first_focus := first.get_theme_stylebox("focus") as StyleBoxFlat
	_check(first.has_theme_stylebox_override("focus"),
		"ボタンのGodot標準フォーカス枠が残っている")
	_check(first_focus != first_hover,
		"キーボード焦点がhoverの枠を重ねるだけになっている")
	_check(first_focus.bg_color == focus_template.bg_color,
		"キーボード焦点で背景色が共通tresの色へ変わらない")
	_check(first_focus.bg_color != first_normal.bg_color,
		"キーボード焦点でも通常時と背景色が同じ")
	_check(first_focus.corner_radius_top_left == first_normal.corner_radius_top_left,
		"共通焦点色の適用でボタン固有の角丸が失われた")
	var first_focus_text := first.get_theme_color("font_focus_color")
	_check(first_focus_text == focus_theme.get_color("font_focus_color", "Button"),
		"キーボード焦点で文字色が共通tresの色へ変わらない")
	_check(absf(first_focus.bg_color.get_luminance() - first_focus_text.get_luminance()) >= 0.55,
		"共通tresの焦点背景と文字の明暗差が小さい")
	var second_pressed := [0]
	second.pressed.connect(func() -> void: second_pressed[0] += 1)
	var first_mouse_filter := first.mouse_filter
	var first_focus_mode := first.focus_mode
	var second_mouse_behavior := second.mouse_behavior_recursive
	var second_focus_behavior := second.focus_behavior_recursive

	var accepted := [false]
	var cancelled := [false]
	service.register_screen(
		screen,
		first,
		func() -> void: cancelled[0] = true,
		func() -> void: accepted[0] = true
	)
	await process_frame
	await process_frame
	_check(first.has_focus(), "画面の初期焦点が先頭へ来ない")
	_check(second.get_theme_stylebox("focus") == intentional_focus,
		"個別指定されたfocus表示を共通基盤が上書きした")
	_check(second.get_theme_color("font_focus_color") == intentional_focus_color,
		"個別指定されたfocus文字色を共通基盤が上書きした")

	var modal := Control.new()
	modal.position = Vector2(420, 40)
	modal.size = Vector2(180, 100)
	modal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	modal.visible = false
	root.add_child(modal)
	var close := Button.new()
	close.text = "閉じる"
	close.size = Vector2(160, 60)
	modal.add_child(close)
	service.register_modal(modal, close, func() -> void: modal.visible = false)
	modal.visible = true
	await process_frame
	await process_frame
	_check(close.has_focus(), "モーダルの中へ焦点が移らない")
	_check(first.get_mouse_filter_with_override() == Control.MOUSE_FILTER_IGNORE,
		"モーダル表示中に背面のマウス入力が残っている")
	_check(first.get_focus_mode_with_override() == Control.FOCUS_NONE,
		"モーダル表示中に背面の方向入力が残っている")
	_check(second.get_mouse_filter_with_override() == Control.MOUSE_FILTER_IGNORE,
		"明示的に有効化された背面Controlが入力ロックを抜けた")
	_check(first.mouse_filter == first_mouse_filter and first.focus_mode == first_focus_mode,
		"入力ロックがControl本来のmouse_filter / focus_modeを書き換えた")

	var late := Button.new()
	late.text = "あとから追加"
	screen.add_child(late)
	# 実行時UIはadd_child()後に見た目を設定することもある。遅い設定にも追従させる。
	var late_normal := StyleBoxFlat.new()
	late_normal.bg_color = Color(0.3, 0.4, 0.2, 1.0)
	late_normal.set_corner_radius_all(23)
	late.add_theme_stylebox_override("normal", late_normal)
	# 画面遷移と同じフレームで追加・破棄されても、遅延focus表示が
	# 破棄済みObjectを引数に受け取って実行時エラーを出さない。
	var short_lived := Button.new()
	screen.add_child(short_lived)
	short_lived.free()
	await process_frame
	await process_frame
	var late_focus := late.get_theme_stylebox("focus") as StyleBoxFlat
	_check(late_focus.bg_color == focus_template.bg_color,
		"動的に増えたボタンの背景が共通焦点色へ変わらない")
	_check(late_focus.corner_radius_top_left == late_normal.corner_radius_top_left,
		"遅れて設定したボタンの角丸を焦点表示が引き継がない")
	_check(late.get_theme_color("font_focus_color") \
			== focus_theme.get_color("font_focus_color", "Button"),
		"動的に増えたボタンの文字が共通焦点色へ変わらない")
	_check(late.get_mouse_filter_with_override() == Control.MOUSE_FILTER_IGNORE,
		"モーダル表示後に増えた背面Controlが入力できる")
	_check(late.get_focus_mode_with_override() == Control.FOCUS_NONE,
		"モーダル表示後に増えた背面Controlへ焦点が移る")
	_check(not service.focus_control(second), "共通APIから背面Controlへ焦点を逃がせる")
	_check(close.has_focus(), "背面の焦点指定でモーダル内の焦点が失われた")
	await _click(second.get_global_rect().get_center())
	_check(second_pressed[0] == 0, "モーダル越しに背面ボタンをクリックできる")

	var nested := Control.new()
	nested.position = Vector2(220, 40)
	nested.size = Vector2(180, 100)
	nested.visible = false
	root.add_child(nested)
	var nested_close := Button.new()
	nested_close.text = "内側を閉じる"
	nested_close.size = Vector2(160, 60)
	nested.add_child(nested_close)
	service.register_modal(nested, nested_close, func() -> void: nested.visible = false)
	nested.visible = true
	await process_frame
	await process_frame
	_check(nested_close.has_focus(), "重ねたモーダルへ焦点が移らない")
	_check(close.get_mouse_filter_with_override() == Control.MOUSE_FILTER_IGNORE,
		"重ねたモーダルの背面になったモーダルをクリックできる")
	_check(close.get_focus_mode_with_override() == Control.FOCUS_NONE,
		"重ねたモーダルの背面へ方向入力が届く")

	service._input(_action(&"ui_cancel"))
	await process_frame
	await process_frame
	_check(not nested.visible, "キャンセルで最前面モーダルが閉じない")
	_check(modal.visible, "内側を閉じたとき外側のモーダルまで閉じた")
	_check(close.has_focus(), "内側を閉じたあと外側へ焦点が戻らない")
	_check(close.get_mouse_filter_with_override() != Control.MOUSE_FILTER_IGNORE,
		"内側を閉じたあと外側モーダルの入力が戻らない")
	_check(first.get_mouse_filter_with_override() == Control.MOUSE_FILTER_IGNORE,
		"内側を閉じたとき背面画面のロックまで外れた")

	service._input(_action(&"ui_cancel"))
	await process_frame
	await process_frame
	_check(not modal.visible, "キャンセルでモーダルが閉じない")
	_check(first.has_focus(), "閉じたあと元の焦点へ戻らない")
	_check(first.get_mouse_filter_with_override() == first_mouse_filter,
		"閉じたあと背面のマウス入力が戻らない")
	_check(first.get_focus_mode_with_override() == first_focus_mode,
		"閉じたあと背面の方向入力が戻らない")
	_check(second.mouse_behavior_recursive == second_mouse_behavior,
		"閉じたあと元のmouse_behavior_recursiveへ戻らない")
	_check(second.focus_behavior_recursive == second_focus_behavior,
		"閉じたあと元のfocus_behavior_recursiveへ戻らない")
	_check(late.mouse_behavior_recursive == Control.MOUSE_BEHAVIOR_INHERITED,
		"動的に増えたControlの入力設定を元へ戻していない")
	var focus_chain_count: int = service.refresh_focus_chain(screen)
	_check(focus_chain_count == 3,
		"動的追加を含む全操作を焦点チェーンへ入れていない: %d" % focus_chain_count)
	var chained: Control = first
	var reached := {}
	for _i in focus_chain_count:
		if chained == null:
			break
		reached[chained.get_instance_id()] = true
		chained = chained.get_node_or_null(chained.focus_neighbor_bottom) as Control
	_check(reached.size() == focus_chain_count,
		"下方向だけで全操作を一周できない: %d/%d" % [reached.size(), focus_chain_count])
	await _click(second.get_global_rect().get_center())
	_check(second_pressed[0] == 1, "モーダルを閉じても背面ボタンをクリックできない")

	var focus := root.gui_get_focus_owner()
	if focus != null:
		focus.release_focus()
	service._input(_action(&"ui_down"))
	_check(first.has_focus(), "焦点が無い状態の方向入力で先頭へ来ない")
	first.release_focus()
	service._input(_action(&"ui_accept"))
	_check(accepted[0], "焦点が無いときの決定を画面へ渡していない")
	service._input(_action(&"ui_cancel"))
	_check(cancelled[0], "画面のキャンセルを呼んでいない")

	_check(_checked >= 44, "GMornUIの検査数が減った: %d" % _checked)
	if not _failures.is_empty():
		for failure in _failures:
			push_error(failure)
		print("GMORN UI VERIFY: FAIL (%d/%d)" % [_failures.size(), _checked])
		quit(1)
		return
	print("画面=1 モーダル=2 背面ロック=1 焦点背景文字=9 動的追加=1 全操作巡回=3 検査=%d" % _checked)
	print("GMORN UI VERIFY: PASS")
	quit(0)


func _action(action: StringName) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	return event


func _click(position: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = position
	event.global_position = position
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame


func _check(condition: bool, message: String) -> void:
	_checked += 1
	if not condition:
		_failures.append(message)
