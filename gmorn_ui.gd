extends Node

## 画面とモーダルの入力範囲を一元管理する。
##
## 画面側は初期焦点、キャンセル、焦点を戻す相手を個別に覚えない。
## `register_screen()` / `register_modal()` だけを呼び、開閉後の焦点復帰と
## `ui_cancel` の配送、背面UIの入力ロックはこのサービスへ任せる。

signal scope_activated(scope: Control)
signal scope_deactivated(scope: Control)

const NAVIGATION_ACTIONS := [
	&"ui_up",
	&"ui_down",
	&"ui_left",
	&"ui_right",
]
const BUTTON_FOCUS_THEME: Theme = preload("button_focus_theme.tres")
const BUTTON_THEME_TYPE := &"Button"

var _screens: Array = []
var _modal_entries: Array = []
var _modal_stack: Array = []
var _input_lock_states: Dictionary = {}
var _managed_button_focus_styles: Dictionary = {}
var _input_lock_refresh_queued := false
var _focus_chain_refresh_queued := false
var _repairing_focus := false
## マウスだけで遊ぶ作品向け。true のあいだは方向入力の焦点を置かず、焦点の色反転も出さず、
## 焦点を持てる Control は追加時に focus_mode = NONE にする（モーダルの背面ロックは効いたまま）。
## 既定は false。作品は project.godot の `gmorn_ui/mouse_only=true` で入れる。検査は実行時に切り替えてよい
var mouse_only: bool = bool(ProjectSettings.get_setting("gmorn_ui/mouse_only", false))


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process_input(true)
	get_tree().node_added.connect(_on_tree_node_added)
	get_viewport().gui_focus_changed.connect(_on_gui_focus_changed)
	_apply_button_focus_visuals(get_tree().root)


## 画面を登録する。`initial` が null なら、方向入力が来るまで焦点を置かない。
##
## `cancel` / `accept` は、焦点のあるControlが入力を処理しなかったときだけ呼ぶ。
## 盤面全体の「Zで送る」「Xでメニューを開く」のような代替操作に使う。
func register_screen(
	scope: Control,
	initial: Control = null,
	cancel: Callable = Callable(),
	accept: Callable = Callable()
) -> void:
	if scope == null:
		return
	_apply_button_focus_visuals(scope)
	unregister(scope)
	var exit_callback := _on_scope_exiting.bind(scope)
	var entry := {
		"scope": scope,
		"initial": initial,
		"cancel": cancel,
		"accept": accept,
		"exit_callback": exit_callback,
	}
	_screens.append(entry)
	scope.tree_exiting.connect(exit_callback)
	if initial != null:
		call_deferred("_focus_entry", entry, false)


## モーダルを登録する。表示中は最前面のscope以外のControlを入力不能にする。
## 表示された瞬間に中へ焦点を移し、閉じたら元へ戻す。
## `cancel` が空なら X では閉じない到達画面として扱う。
func register_modal(
	scope: Control,
	initial: Control = null,
	cancel: Callable = Callable()
) -> void:
	if scope == null:
		return
	_apply_button_focus_visuals(scope)
	unregister(scope)
	var visibility_callback := _on_modal_visibility_changed.bind(scope)
	var exit_callback := _on_scope_exiting.bind(scope)
	var entry := {
		"scope": scope,
		"initial": initial,
		"cancel": cancel,
		"accept": Callable(),
		"restore": null,
		"visibility_callback": visibility_callback,
		"exit_callback": exit_callback,
	}
	_modal_entries.append(entry)
	scope.visibility_changed.connect(visibility_callback)
	scope.tree_exiting.connect(exit_callback)
	if scope.is_inside_tree():
		_sync_modal(scope)
	else:
		call_deferred("_sync_modal", scope)


func unregister(scope: Control) -> void:
	var screen := _entry_for(scope, _screens)
	if not screen.is_empty():
		_disconnect_entry(screen)
		_screens.erase(screen)
	var modal := _entry_for(scope, _modal_entries)
	if not modal.is_empty():
		var was_active := _modal_stack.has(modal)
		_deactivate_modal(modal)
		_disconnect_entry(modal)
		_modal_entries.erase(modal)
		if was_active:
			scope_deactivated.emit(scope)


## 次に表示したときの初期焦点を差し替える。
## セーブ一覧のように、開き方で先頭が変わるモーダルに使う。
func set_initial(scope: Control, initial: Control) -> void:
	var entry := _entry_for(scope, _modal_entries)
	if entry.is_empty():
		entry = _entry_for(scope, _screens)
	if not entry.is_empty():
		entry["initial"] = initial
		_queue_focus_chain_refresh()


## 表示中かつ有効な全操作を、上／下だけでも必ず一周できるようにつなぐ。
##
## 自動配置へ任せるだけでは、重なったパネルや画面端の操作へ辿れない組み合わせが生じる。
## 画面上の並び順で上下の循環を明示し、動的一覧は作り直すたびにこの関数を呼ぶ。
## 戻り値はつないだ操作数。0件を成功として扱わない検査にも使える。
func refresh_focus_chain(scope: Control) -> int:
	if scope == null or not scope.is_inside_tree():
		return 0
	var controls: Array = []
	_collect_focusable(scope, scope, controls)
	controls.sort_custom(_focus_order)
	if controls.size() == 1:
		controls[0].focus_neighbor_top = NodePath("")
		controls[0].focus_neighbor_bottom = NodePath("")
		return 1
	for i in controls.size():
		var control := controls[i] as Control
		var previous := controls[(i - 1 + controls.size()) % controls.size()] as Control
		var following := controls[(i + 1) % controls.size()] as Control
		control.focus_neighbor_top = control.get_path_to(previous)
		control.focus_neighbor_bottom = control.get_path_to(following)
	return controls.size()


## `scope` 内の押せる先頭へ焦点を置く。動的に作り直す一覧にも使える。
func focus_first(scope: Control, preferred: Control = null) -> bool:
	if mouse_only:
		return false
	if scope == null or not scope.is_inside_tree() or not _inside_active_scope(scope):
		return false
	refresh_focus_chain(scope)
	var target := preferred
	if not _can_focus(target, scope):
		target = _first_focusable(scope)
	if target == null:
		return false
	target.grab_focus()
	return true


## 特定のControlへ焦点を置く。現在の画面／モーダルの外には移さない。
func focus_control(control: Control) -> bool:
	if mouse_only:
		return false
	var active := _active_entry()
	if active.is_empty() or not _can_focus(control, active["scope"]):
		return false
	refresh_focus_chain(active["scope"])
	control.grab_focus()
	return true


func is_focusable(control: Control, scope: Control = null) -> bool:
	return _can_focus(control, scope)


func is_active_scope(scope: Control) -> bool:
	var active := _active_entry()
	return not active.is_empty() and active["scope"] == scope


## GUIより先に受ける。焦点中のControlが `ui_cancel` を消費しても、最前面の
## モーダルを必ず閉じられるようにするためである。処理した入力はその場で止め、
## 閉じた直後の背面ボタンへ同じ入力が届かないようにする。
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.echo:
		return
	var active := _active_entry()
	if active.is_empty():
		return

	if event.is_action_pressed(&"ui_cancel"):
		var cancel: Callable = active["cancel"]
		if cancel.is_valid():
			cancel.call()
			get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed(&"ui_accept"):
		var focus := get_viewport().gui_get_focus_owner()
		if not _can_focus(focus, active["scope"]):
			var accept: Callable = active["accept"]
			if accept.is_valid():
				accept.call()
				get_viewport().set_input_as_handled()
		return

	for action in NAVIGATION_ACTIONS:
		if not event.is_action_pressed(action):
			continue
		var focus := get_viewport().gui_get_focus_owner()
		if not _can_focus(focus, active["scope"]):
			if focus_first(active["scope"], active["initial"]):
				get_viewport().set_input_as_handled()
			return
		# Godotの幾何探索だけでは、重なったパネルや離れた隅ボタンを飛ばすことがある。
		# 上下は共通チェーンへ直接配送し、どの配置でも全操作を一周できるようにする。
		if action == &"ui_up" or action == &"ui_down":
			refresh_focus_chain(active["scope"])
			var path := focus.focus_neighbor_top if action == &"ui_up" else focus.focus_neighbor_bottom
			var target := focus.get_node_or_null(path) as Control
			if _can_focus(target, active["scope"]):
				target.grab_focus()
				get_viewport().set_input_as_handled()
		return


func _on_modal_visibility_changed(scope: Control) -> void:
	_sync_modal(scope)


func _sync_modal(scope: Control) -> void:
	if not is_instance_valid(scope):
		return
	var entry := _entry_for(scope, _modal_entries)
	if entry.is_empty():
		return
	if scope.is_visible_in_tree():
		if not _modal_stack.has(entry):
			_activate_modal(entry)
			scope_activated.emit(scope)
	else:
		if _modal_stack.has(entry):
			_deactivate_modal(entry)
			scope_deactivated.emit(scope)


func _activate_modal(entry: Dictionary) -> void:
	var scope: Control = entry["scope"]
	if _modal_stack.has(entry):
		_modal_stack.erase(entry)
	else:
		var previous := get_viewport().gui_get_focus_owner()
		entry["restore"] = weakref(previous) if previous != null else null
	_modal_stack.append(entry)
	_refresh_modal_input_lock()
	call_deferred("_focus_entry", entry, true)


func _deactivate_modal(entry: Dictionary) -> void:
	if not _modal_stack.has(entry):
		return
	var was_top: bool = _modal_stack.back() == entry
	_modal_stack.erase(entry)
	if not was_top:
		return
	var focus := get_viewport().gui_get_focus_owner()
	var scope: Control = entry["scope"]
	_refresh_modal_input_lock()
	if is_instance_valid(focus) and (focus == scope or scope.is_ancestor_of(focus)):
		focus.release_focus()
	call_deferred("_restore_focus", entry.get("restore"))


## 最前面モーダル以外を、見た目や各ボタンのdisabledを変えずに入力不能にする。
## Godot 4.5以降の再帰入力設定を使うため、動的に増えた子Controlにも継承される。
func _refresh_modal_input_lock() -> void:
	_input_lock_refresh_queued = false
	_restore_modal_input_lock()
	_apply_modal_input_lock()


func _apply_modal_input_lock() -> void:
	var modal := _active_modal_scope()
	if modal == null:
		return
	_lock_controls_outside(get_tree().root, modal)


func _lock_controls_outside(node: Node, modal: Control) -> void:
	var control := node as Control
	if control == modal:
		_set_recursive_input(control, true)
		return
	if control != null:
		_set_recursive_input(control, false)
	for child in node.get_children():
		_lock_controls_outside(child, modal)


func _set_recursive_input(control: Control, enabled: bool) -> void:
	var instance_id := control.get_instance_id()
	if not _input_lock_states.has(instance_id):
		_input_lock_states[instance_id] = {
			"control": weakref(control),
			"mouse": control.mouse_behavior_recursive,
			"focus": control.focus_behavior_recursive,
		}
	control.mouse_behavior_recursive = (
		Control.MOUSE_BEHAVIOR_ENABLED if enabled else Control.MOUSE_BEHAVIOR_DISABLED
	)
	control.focus_behavior_recursive = (
		Control.FOCUS_BEHAVIOR_ENABLED if enabled else Control.FOCUS_BEHAVIOR_DISABLED
	)


func _restore_modal_input_lock() -> void:
	for value: Variant in _input_lock_states.values():
		var state := value as Dictionary
		var reference := state.get("control") as WeakRef
		if reference == null:
			continue
		var control := reference.get_ref() as Control
		if not is_instance_valid(control):
			continue
		control.mouse_behavior_recursive = state["mouse"]
		control.focus_behavior_recursive = state["focus"]
	_input_lock_states.clear()


func _on_tree_node_added(node: Node) -> void:
	if not node is Control:
		return
	if mouse_only:
		_strip_focus(node as Control)
	var button := node as Button
	if button != null:
		_apply_button_focus_visual(button)
		# SceneTreeへ入った直後に作成側がhoverを設定する場合へ追従する。
		# 生のButtonを遅延引数にすると、同じフレームで画面が切り替わったとき
		# 呼び出し前に破棄され、型付き引数へ変換する段階で実行時エラーになる。
		call_deferred("_apply_deferred_button_focus_visual", weakref(button))
	_queue_focus_chain_refresh()
	if _active_modal_scope() == null or _input_lock_refresh_queued:
		return
	_input_lock_refresh_queued = true
	call_deferred("_refresh_modal_input_lock")


func _queue_focus_chain_refresh() -> void:
	if _focus_chain_refresh_queued:
		return
	_focus_chain_refresh_queued = true
	call_deferred("_refresh_active_focus_chain")


func _refresh_active_focus_chain() -> void:
	_focus_chain_refresh_queued = false
	var active := _active_entry()
	if not active.is_empty():
		refresh_focus_chain(active["scope"])


## キーボード焦点を、枠の追加ではなく背景色と文字色の反転で示す。
## 色は `button_focus_theme.tres` に集め、形は各ボタンのnormalから引き継ぐ。
## 個別にfocus表示を指定したボタンは、作品固有の意図としてそのまま残す。
func _apply_button_focus_visuals(node: Node) -> void:
	if not is_instance_valid(node):
		return
	var button := node as Button
	if button != null:
		_apply_button_focus_visual(button)
	for child in node.get_children():
		_apply_button_focus_visuals(child)


func _apply_deferred_button_focus_visual(reference: WeakRef) -> void:
	if reference == null:
		return
	var button := reference.get_ref() as Button
	if not is_instance_valid(button):
		return
	_apply_button_focus_visual(button)


## mouse_only: 文字入力以外は焦点を持たせない（押しても金に反転しない。方向入力でも移らない）
func _strip_focus(control: Control) -> void:
	if control == null or control is LineEdit or control is TextEdit:
		return
	if control.focus_mode != Control.FOCUS_NONE:
		control.focus_mode = Control.FOCUS_NONE


func _apply_button_focus_visual(button: Button) -> void:
	if mouse_only:
		return
	var instance_id := button.get_instance_id()
	var tracked := _managed_button_focus_styles.get(instance_id, {}) as Dictionary
	if not tracked.is_empty():
		var reference := tracked.get("button") as WeakRef
		if reference == null or reference.get_ref() != button:
			_managed_button_focus_styles.erase(instance_id)
			tracked = {}
	var manages_style := bool(tracked.get("manages_style", false))
	var manages_color := bool(tracked.get("manages_color", false))
	if not tracked.is_empty():
		var managed_style := tracked.get("style") as StyleBox
		if manages_style and (not button.has_theme_stylebox_override(&"focus") \
				or button.get_theme_stylebox(&"focus") != managed_style):
			# 追加後に作品側がfocus表示を指定した。以後、その項目は上書きしない。
			manages_style = false
		var managed_color := tracked.get("color", Color.TRANSPARENT) as Color
		if manages_color and (not button.has_theme_color_override(&"font_focus_color") \
				or not button.get_theme_color(&"font_focus_color").is_equal_approx(managed_color)):
			manages_color = false
	else:
		manages_style = not button.has_theme_stylebox_override(&"focus")
		manages_color = not button.has_theme_color_override(&"font_focus_color")
	if not manages_style and not manages_color:
		_managed_button_focus_styles.erase(instance_id)
		return
	var focus_style: StyleBox
	if manages_style:
		focus_style = make_button_focus_style(button.get_theme_stylebox(&"normal"))
		button.add_theme_stylebox_override(&"focus", focus_style)
	var focus_color := button_focus_text_color()
	if manages_color:
		button.add_theme_color_override(&"font_focus_color", focus_color)
	var exit_callback := _on_managed_button_exiting.bind(instance_id)
	if not button.tree_exiting.is_connected(exit_callback):
		button.tree_exiting.connect(exit_callback, CONNECT_ONE_SHOT)
	_managed_button_focus_styles[instance_id] = {
		"button": weakref(button),
		"manages_style": manages_style,
		"manages_color": manages_color,
		"style": focus_style,
		"color": focus_color,
	}


## 共通の焦点色を使いつつ、角丸と余白は元の部品から引き継ぐ。
## Button以外の独自操作も同じ見た目へ揃えられるよう公開している。
func make_button_focus_style(base_style: StyleBox) -> StyleBoxFlat:
	var template := BUTTON_FOCUS_THEME.get_stylebox(&"focus", BUTTON_THEME_TYPE) as StyleBoxFlat
	var style := template.duplicate() as StyleBoxFlat
	var flat_base := base_style as StyleBoxFlat
	if flat_base != null:
		style = flat_base.duplicate() as StyleBoxFlat
		style.bg_color = template.bg_color
		style.border_color = template.border_color
		style.border_width_left = template.border_width_left
		style.border_width_top = template.border_width_top
		style.border_width_right = template.border_width_right
		style.border_width_bottom = template.border_width_bottom
	return style


func button_focus_text_color() -> Color:
	return BUTTON_FOCUS_THEME.get_color(&"font_focus_color", BUTTON_THEME_TYPE)


func _on_managed_button_exiting(instance_id: int) -> void:
	_managed_button_focus_styles.erase(instance_id)


func _on_gui_focus_changed(control: Control) -> void:
	var modal := _active_modal_scope()
	if modal == null or control == null or control == modal or modal.is_ancestor_of(control):
		return
	if _repairing_focus:
		return
	_repairing_focus = true
	control.release_focus()
	focus_first(modal)
	_repairing_focus = false


func _active_modal_scope() -> Control:
	if _modal_stack.is_empty():
		return null
	var entry: Dictionary = _modal_stack.back()
	var scope := entry.get("scope") as Control
	if not is_instance_valid(scope) or not scope.is_inside_tree() or not scope.is_visible_in_tree():
		return null
	return scope


func _restore_focus(previous_ref) -> void:
	if mouse_only:
		return
	var active := _active_entry()
	var previous := previous_ref.get_ref() as Control if previous_ref is WeakRef else null
	if active.is_empty():
		# 画面を登録していない作品でも、モーダルを閉じたら開く前の焦点へ戻す。
		if _can_focus(previous):
			previous.grab_focus()
		return
	var scope: Control = active["scope"]
	if _can_focus(previous, scope):
		previous.grab_focus()
		return
	var initial := active["initial"] as Control
	if initial != null:
		focus_first(scope, initial)


func _focus_entry(entry: Dictionary, use_fallback: bool) -> void:
	if _active_entry() != entry:
		return
	var scope: Control = entry["scope"]
	var initial := entry["initial"] as Control
	if initial != null:
		focus_first(scope, initial)
	elif use_fallback:
		focus_first(scope)


func _on_scope_exiting(scope: Control) -> void:
	unregister(scope)


func _active_entry() -> Dictionary:
	while not _modal_stack.is_empty():
		var entry: Dictionary = _modal_stack.back()
		var scope := entry.get("scope") as Control
		if is_instance_valid(scope) and scope.is_inside_tree() and scope.is_visible_in_tree():
			return entry
		_modal_stack.pop_back()
	for i in range(_screens.size() - 1, -1, -1):
		var entry: Dictionary = _screens[i]
		var scope := entry.get("scope") as Control
		if is_instance_valid(scope) and scope.is_inside_tree() and scope.is_visible_in_tree():
			return entry
	return {}


func _inside_active_scope(scope: Control) -> bool:
	var active := _active_entry()
	if active.is_empty():
		return false
	var active_scope: Control = active["scope"]
	return scope == active_scope or active_scope.is_ancestor_of(scope)


func _first_focusable(scope: Control) -> Control:
	var controls: Array = []
	_collect_focusable(scope, scope, controls)
	return controls[0] if not controls.is_empty() else null


func _collect_focusable(node: Node, scope: Control, out: Array) -> void:
	var control := node as Control
	if control != null and _can_focus(control, scope):
		out.append(control)
	for child in node.get_children():
		_collect_focusable(child, scope, out)


func _focus_order(a: Control, b: Control) -> bool:
	var a_center := a.get_global_rect().get_center()
	var b_center := b.get_global_rect().get_center()
	if not is_equal_approx(a_center.y, b_center.y):
		return a_center.y < b_center.y
	if not is_equal_approx(a_center.x, b_center.x):
		return a_center.x < b_center.x
	return str(a.get_path()) < str(b.get_path())


func _can_focus(control: Control, scope: Control = null) -> bool:
	if not is_instance_valid(control) or control.is_queued_for_deletion():
		return false
	if not control.is_inside_tree() or not control.is_visible_in_tree():
		return false
	# FOCUS_CLICK と FOCUS_ACCESSIBILITY は方向入力の対象ではない。
	# 「NONEではない」だけで集めると、読み上げ専用Controlへ移動して焦点を失う。
	if control.get_focus_mode_with_override() != Control.FOCUS_ALL:
		return false
	if control is BaseButton and control.disabled:
		return false
	if scope != null and control != scope and not scope.is_ancestor_of(control):
		return false
	return true


func _entry_for(scope: Control, entries: Array) -> Dictionary:
	for entry in entries:
		if entry.get("scope") == scope:
			return entry
	return {}


func _disconnect_entry(entry: Dictionary) -> void:
	var scope := entry.get("scope") as Control
	if not is_instance_valid(scope):
		return
	var visibility_callback := entry.get("visibility_callback", Callable()) as Callable
	if visibility_callback.is_valid() and scope.visibility_changed.is_connected(visibility_callback):
		scope.visibility_changed.disconnect(visibility_callback)
	var exit_callback := entry.get("exit_callback", Callable()) as Callable
	if exit_callback.is_valid() and scope.tree_exiting.is_connected(exit_callback):
		scope.tree_exiting.disconnect(exit_callback)
