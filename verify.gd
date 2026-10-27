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
	var controls: Array = [first, second, late]
	var reached := {first.get_instance_id(): true}
	var frontier: Array = [first]
	while not frontier.is_empty():
		var current: Control = frontier.pop_back()
		for side: Side in [SIDE_TOP, SIDE_BOTTOM, SIDE_LEFT, SIDE_RIGHT]:
			var next: Control = service.find_neighbor(current, side, screen)
			if next != null and not reached.has(next.get_instance_id()):
				reached[next.get_instance_id()] = true
				frontier.append(next)
	_check(reached.size() == controls.size(),
		"動的追加を含む全操作へ方向入力で辿れない: %d/%d" % [reached.size(), controls.size()])
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

	# --- シーンに置く部品（GMornUIModal）---
	# 画面を登録していない作品でも、置くだけで背面を止め、閉じたら開く前の焦点へ戻すこと。
	service.unregister(screen)
	service.name = "GMornUI"
	first.grab_focus()
	var piece_modal := PanelContainer.new()
	piece_modal.visible = false
	var piece_close := Button.new()
	piece_close.text = "部品で閉じる"
	piece_modal.add_child(piece_close)
	var piece: Node = load(UI_PATH.get_base_dir().path_join("gmorn_ui_modal.gd")).new()
	piece.initial = piece_close
	piece.cancelled.connect(func() -> void: piece_modal.visible = false)
	piece_modal.add_child(piece)
	root.add_child(piece_modal)
	await process_frame
	piece_modal.visible = true
	await process_frame
	await process_frame
	_check(piece_close.has_focus(), "部品を置いたモーダルへ焦点が移らない")
	_check(first.get_focus_mode_with_override() == Control.FOCUS_NONE,
		"部品を置いたモーダルの背面へ方向入力が届く")
	piece.active = false
	await process_frame
	_check(first.get_focus_mode_with_override() != Control.FOCUS_NONE and first.has_focus(),
		"active を切っても、見えている間は背面が止まったまま")
	piece.active = true
	await process_frame
	await process_frame
	_check(piece_close.has_focus(), "active を戻してもモーダルへ焦点が移らない")
	service._input(_action(&"ui_cancel"))
	await process_frame
	await process_frame
	_check(not piece_modal.visible, "部品の cancelled で閉じない")
	_check(first.has_focus(), "画面を登録していなくても、閉じたあと元の焦点へ戻らない")
	piece_modal.queue_free()
	await process_frame

	# 焦点の持ち主が消えたら、同じ位置か近くへ戻す。作品が意図して外した焦点には触らない。
	var list := VBoxContainer.new()
	root.add_child(list)
	var head := Button.new()
	head.name = "Head"
	var row := Button.new()
	row.name = "Row"
	list.add_child(head)
	list.add_child(row)
	await process_frame
	row.grab_focus()
	await process_frame
	list.remove_child(row)
	row.queue_free()
	var rebuilt := Button.new()
	rebuilt.name = "Row"
	rebuilt.disabled = true
	list.add_child(rebuilt)
	await process_frame
	_check(rebuilt.has_focus(), "作り直した同じ位置の釦（無効でも）へ焦点が戻らない")
	list.remove_child(rebuilt)
	rebuilt.queue_free()
	await process_frame
	_check(head.has_focus(), "焦点の釦が消えたとき、近くの押せる物へ焦点が戻らない")
	head.release_focus()
	await process_frame
	await process_frame
	_check(get_root().gui_get_focus_owner() == null, "作品が意図して外した焦点を勝手に戻した")
	# モーダルの裏で焦点の釦が作り直されても、閉じたら作り直した釦へ戻す。
	var behind := Button.new()
	behind.name = "Behind"
	list.add_child(behind)
	behind.grab_focus()
	await process_frame
	var cover := PanelContainer.new()
	cover.hide()
	var cover_button := Button.new()
	cover.add_child(cover_button)
	root.add_child(cover)
	service.register_modal(cover, cover_button)
	cover.show()
	await process_frame
	await process_frame
	list.remove_child(behind)
	behind.queue_free()
	var behind_again := Button.new()
	behind_again.name = "Behind"
	list.add_child(behind_again)
	await process_frame
	cover.hide()
	await process_frame
	await process_frame
	_check(behind_again.has_focus(), "モーダルの裏で作り直した釦へ、閉じたあと焦点が戻らない")
	cover.queue_free()
	list.queue_free()

	# 上の行の釦が下の釦より右へ2pxはみ出しても、右は同じ行の釦へ行く。
	var grid_host := Control.new()
	root.add_child(grid_host)
	var cells: Array[Button] = []
	for rect: Rect2 in [Rect2(0, 0, 436, 80), Rect2(460, 0, 427, 80), Rect2(6, 100, 428, 80), Rect2(460, 100, 427, 80)]:
		var cell := Button.new()
		cell.position = rect.position
		cell.size = rect.size
		grid_host.add_child(cell)
		cells.append(cell)
	await process_frame
	_check(service.find_neighbor(cells[2], SIDE_RIGHT) == cells[3],
		"上の行の釦が数pxはみ出すと、右で同じ行の釦へ行かない")
	grid_host.queue_free()

	_check(_checked >= 54, "GMornUIの検査数が減った: %d" % _checked)
	if not _failures.is_empty():
		for failure in _failures:
			push_error(failure)
		print("GMORN UI VERIFY: FAIL (%d/%d)" % [_failures.size(), _checked])
		quit(1)
		return
	print("画面=1 モーダル=2 背面ロック=1 焦点背景文字=9 動的追加=1 全操作巡回=3 検査=%d" % _checked)
	# --- 文字の大きさの組（GMornFontSize）---
	# 名前で登録した大きさが親に当たること。名前を変えれば追従し、無い名前は当てないこと。
	var font_size_script: GDScript = load(UI_PATH.get_base_dir().path_join("gmorn_font_size.gd"))
	ProjectSettings.set_setting("gmorn_ui/font_sizes", {"note": 21, "title": 40})
	assert(font_size_script.names() == PackedStringArray(["note", "title"]), "登録した名前が順に並ぶはず")
	var label := Label.new()
	root.add_child(label)
	var sizer: Node = font_size_script.new()
	label.add_child(sizer)
	sizer.preset = "note"
	assert(label.get_theme_font_size("font_size") == 21, "登録した大きさが親の Label に当たらない")
	sizer.preset = "title"
	assert(label.get_theme_font_size("font_size") == 40, "名前を変えても追従しない")
	sizer.preset = "unknown"
	assert(label.get_theme_font_size("font_size") == 40, "無い名前で大きさが変わってはいけない")
	var rich := RichTextLabel.new()
	root.add_child(rich)
	var rich_sizer: Node = font_size_script.new()
	rich.add_child(rich_sizer)
	rich_sizer.preset = "note"
	assert(rich.get_theme_font_size("bold_font_size") == 21, "RichTextLabel の太字にも同じ大きさが当たるはず")
	print("文字の組: note=21 / title=40 を Label / RichTextLabel に当てた")

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
