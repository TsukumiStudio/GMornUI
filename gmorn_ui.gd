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
const NAVIGATION_SIDES: Array[Side] = [SIDE_TOP, SIDE_BOTTOM, SIDE_LEFT, SIDE_RIGHT]
const REPEAT_DELAY_SETTING := "gmorn_ui/navigation_repeat_delay"
const REPEAT_INTERVAL_SETTING := "gmorn_ui/navigation_repeat_interval"
const REPEAT_DELAY_DEFAULT := 0.4
const REPEAT_INTERVAL_DEFAULT := 0.12
const BUTTON_FOCUS_THEME: Theme = preload("button_focus_theme.tres")
const BUTTON_THEME_TYPE := &"Button"

var _screens: Array = []
var _modal_entries: Array = []
var _modal_stack: Array = []
var _input_lock_states: Dictionary = {}
var _managed_button_focus_styles: Dictionary = {}
var _input_lock_refresh_queued := false
var _repairing_focus := false
## 直前の焦点。押した釦が作り直し・非表示・削除で消えたとき、同じ位置か近くへ戻すために控える。
var _last_focus: Dictionary = {}
## マウスだけで遊ぶ作品向け。true のあいだは方向入力の焦点を置かず、焦点の色反転も出さず、
## 焦点を持てる Control は追加時に focus_mode = NONE にする（モーダルの背面ロックは効いたまま）。
## 既定は false。作品は project.godot の `gmorn_ui/mouse_only=true` で入れる。検査は実行時に切り替えてよい
var mouse_only: bool = bool(ProjectSettings.get_setting("gmorn_ui/mouse_only", false))
## 方向を押し続けたとき、繰り返しに入るまでの秒数と、その後の間隔（`project.godot` の `gmorn_ui/` で変える）。
## スティックは倒している間ずっと入力が届き、鍵盤の繰り返しは OS の速さで来るので、どちらも自前で間引く。
var navigation_repeat_delay: float = float(ProjectSettings.get_setting(REPEAT_DELAY_SETTING, REPEAT_DELAY_DEFAULT))
var navigation_repeat_interval: float = float(ProjectSettings.get_setting(REPEAT_INTERVAL_SETTING, REPEAT_INTERVAL_DEFAULT))
## 押し続けている方向（NAVIGATION_ACTIONS の番号）と、次に繰り返すまでの残り秒数。-1 は押していない。
var _held_navigation := -1
var _repeat_left := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process_input(true)
	set_process(true)
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
		"restore": {},
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


## 互換のために残す。上下の行き先は `find_neighbor()` が中心の位置で決めるので、読み順の配線は要らない。
## 戻り値は `scope` 内の焦点を持てる操作数（0件を成功として扱わない検査向け）。
func refresh_focus_chain(scope: Control) -> int:
	if scope == null or not scope.is_inside_tree():
		return 0
	var controls: Array = []
	_collect_focusable(scope, scope, controls)
	return controls.size()


## `scope` 内の押せる先頭へ焦点を置く。動的に作り直す一覧にも使える。
func focus_first(scope: Control, preferred: Control = null) -> bool:
	if mouse_only:
		return false
	if scope == null or not scope.is_inside_tree() or not _inside_active_scope(scope):
		return false
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
		# 繰り返しは自前で送るので捨てる。滑り棒・文字入力は長押しで動かすので通す。
		if _is_navigation_event(event) and not _uses_arrows(get_viewport().gui_get_focus_owner()):
			get_viewport().set_input_as_handled()
		return
	var active := _active_entry()
	if active.is_empty():
		_navigate(event, active)
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

	_navigate(event, active)


## 方向入力の行き先はすべてここで決める。Godot の位置探しは矩形の端で比べるので、
## 隣の列より数 px はみ出しただけの上の行の釦を「右にある」と選ぶ。
func _navigate(event: InputEvent, active: Dictionary) -> void:
	# 素早く離して押し直したとき、次のこまを待たずに新しい押下として受ける。
	if _held_navigation >= 0 and event.is_action_released(NAVIGATION_ACTIONS[_held_navigation]):
		_held_navigation = -1
	for index in NAVIGATION_ACTIONS.size():
		if not event.is_action_pressed(NAVIGATION_ACTIONS[index]):
			continue
		# 押し続けの間に届く同じ向きの入力（スティック）は、繰り返しの時刻まで捨てる。
		var repeat := index == _held_navigation
		if not repeat:
			_held_navigation = index
			_repeat_left = navigation_repeat_delay
		if _move_focus(index, active, not repeat):
			get_viewport().set_input_as_handled()
		return


## 押し続けを見て、待ってから一定の間隔で同じ向きへ送る。
func _repeat_navigation(delta: float) -> void:
	if _held_navigation < 0:
		return
	if not Input.is_action_pressed(NAVIGATION_ACTIONS[_held_navigation]):
		_held_navigation = -1
		return
	_repeat_left -= delta
	if _repeat_left > 0.0:
		return
	_repeat_left = navigation_repeat_interval
	_move_focus(_held_navigation, _active_entry(), true)


func _is_navigation_event(event: InputEvent) -> bool:
	for action in NAVIGATION_ACTIONS:
		if event.is_action(action):
			return true
	return false


## 方向入力を1回ぶん処理し、受けたら true（呼ぶ側が Godot の位置探しへ渡さず止める）。
## `move` が false なら動かさず、受けるかどうかだけを返す（押し続けの間に届く入力を捨てるとき）。
func _move_focus(index: int, active: Dictionary, move: bool) -> bool:
	var scope: Control = active["scope"] if not active.is_empty() else null
	var focus := get_viewport().gui_get_focus_owner()
	if focus == null or (scope != null and not _can_hold_focus(focus, scope)):
		return scope != null and move and focus_first(scope, active["initial"])
	# 矢印を自分の操作に使う部品（滑り棒・文字入力・一覧）は、その部品に任せる。
	if _uses_arrows(focus):
		return false
	var target := find_neighbor(focus, NAVIGATION_SIDES[index], scope)
	if move and target != null:
		target.grab_focus()
	# 画面・モーダルの中では行き先が無くても止める（Godot の位置探しへ渡すと矩形の端で比べて斜めへ飛ぶ）。
	# 登録の無い所では、行き先が無ければ作品の処理（矢印で潰す等）へ流す。
	return scope != null or target != null


## `from` から `side` の向きの行き先。順に、
## 1. 釦に明示した隣（`focus_neighbor_*`）
## 2. 中心がその向きの先にあるものから、同じ行（上下なら同じ列）を優先して最も近いもの
## 3. 上下でそれも無ければ、画面上の読み順の前後（端では折り返す）。どの配置でも全操作を辿れる
## 押せない釦も行き先に含める（焦点の位置で何が押せないかを示す）。
func find_neighbor(from: Control, side: Side, scope: Control = null) -> Control:
	var explicit := from.get_node_or_null(from.get_focus_neighbor(side)) as Control
	if _can_hold_focus(explicit, scope):
		return explicit
	var candidates: Array = []
	_collect_holdable(scope if scope != null else get_tree().root, scope, candidates)
	candidates.erase(from)
	var origin := from.get_global_rect()
	var horizontal := side == SIDE_LEFT or side == SIDE_RIGHT
	var direction := 1.0 if side == SIDE_RIGHT or side == SIDE_BOTTOM else -1.0
	var best: Control = null
	var best_key := []
	for item in candidates:
		var candidate := item as Control
		var rect := candidate.get_global_rect()
		var delta := rect.get_center() - origin.get_center()
		var along := (delta.x if horizontal else delta.y) * direction
		if along <= 0.5:
			continue
		var across := absf(delta.y if horizontal else delta.x)
		var overlaps := (rect.position.y < origin.end.y and origin.position.y < rect.end.y) if horizontal \
			else (rect.position.x < origin.end.x and origin.position.x < rect.end.x)
		var key := [0 if overlaps else 1, along + across * 2.0]
		if best == null or key < best_key:
			best = candidate
			best_key = key
	# 読み順の折り返しは画面・モーダルの中だけ。登録の無い所で折り返すと、画面外の釦まで候補になる。
	if best != null or horizontal or scope == null:
		return best
	candidates.append(from)
	candidates.sort_custom(_focus_order)
	var position := candidates.find(from)
	if candidates.size() < 2:
		return null
	return candidates[posmod(position + int(direction), candidates.size())]


func _collect_holdable(node: Node, scope: Control, out: Array) -> void:
	var control := node as Control
	if control != null and _can_hold_focus(control, scope):
		out.append(control)
	for child in node.get_children():
		_collect_holdable(child, scope, out)


func _uses_arrows(control: Control) -> bool:
	return control is Range or control is LineEdit or control is TextEdit \
		or control is ItemList or control is Tree or control is TabBar


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
		entry["restore"] = _focus_record(previous) if previous != null else {}
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
	call_deferred("_restore_focus", entry.get("restore", {}))


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
	if _active_modal_scope() == null or _input_lock_refresh_queued:
		return
	_input_lock_refresh_queued = true
	call_deferred("_refresh_modal_input_lock")


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
	if control != null:
		_last_focus = _focus_record(control)
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


func _restore_focus(record: Dictionary) -> void:
	if mouse_only:
		return
	var active := _active_entry()
	var scope: Control = active["scope"] if not active.is_empty() else null
	if _focus_from_record(record, scope):
		return
	var initial := active.get("initial") as Control
	if initial != null:
		focus_first(scope, initial)


## 焦点の持ち主が消えたかを毎フレーム見る。
##
## 押した釦が一覧の作り直しで捨てられたり、親ごと隠れたりすると Godot は焦点を黙って外す。
## 画面側で個別に戻すと戻し忘れが必ず出るので、ここで一元的に拾う。
## 持ち主がまだ見えているのに焦点が無いのは、作品が意図して外した（`release_focus()`）ものとして触らない。
func _process(delta: float) -> void:
	if mouse_only:
		return
	# 押し続けの間隔は実時間で測る（`Engine.time_scale` で操作の速さが変わらないように）。
	_repeat_navigation(delta / maxf(Engine.time_scale, 0.001))
	var owner := get_viewport().gui_get_focus_owner()
	if owner != null:
		if _last_focus.get("control") is WeakRef and _last_focus["control"].get_ref() == owner:
			return
		_last_focus = _focus_record(owner)
		return
	if _last_focus.is_empty():
		return
	var record := _last_focus
	_last_focus = {}
	var lost := (record["control"] as WeakRef).get_ref() as Control
	if is_instance_valid(lost) and lost.is_inside_tree() and lost.is_visible_in_tree() \
			and not lost.is_queued_for_deletion():
		return
	var modal := _active_modal_scope()
	if modal != null and not str(record["path"]).begins_with(str(modal.get_path()) + "/"):
		# 前面のモーダルの裏で消えた。閉じたときの戻し先だけ、同じ位置で引けるよう控えておく。
		return
	# 画面の中で消えたなら画面の中へ、画面の外（未登録の部分）なら近い祖先の中へ戻す。
	var active := _active_entry()
	var scope: Control = active["scope"] if not active.is_empty() else null
	if scope != null and not str(record["path"]).begins_with(str(scope.get_path()) + "/"):
		scope = null
	_focus_from_record(record, scope)


func _focus_record(control: Control) -> Dictionary:
	return {"control": weakref(control), "path": control.get_path()}


## 控えた焦点へ戻す。本人が居なければ同じパスの作り直された Control（買えなくなって無効でも
## 同じ位置に置く）、それも無ければ近い祖先の中の押せる先頭へ置く。
func _focus_from_record(record: Dictionary, scope: Control) -> bool:
	if record.is_empty():
		return false
	var previous := (record["control"] as WeakRef).get_ref() as Control
	if _can_focus(previous, scope):
		previous.grab_focus()
		return true
	var path: NodePath = record["path"]
	var same := get_node_or_null(path) as Control
	if _can_hold_focus(same, scope):
		same.grab_focus()
		return true
	for depth in range(path.get_name_count() - 1, 0, -1):
		var names: PackedStringArray = []
		for i in depth:
			names.append(path.get_name(i))
		var ancestor := get_node_or_null(NodePath("/" + "/".join(names))) as Control
		if ancestor == null or not ancestor.is_visible_in_tree():
			continue
		if scope != null and ancestor != scope and not scope.is_ancestor_of(ancestor) \
				and not ancestor.is_ancestor_of(scope):
			return false
		var target := _first_focusable(scope if scope != null and ancestor.is_ancestor_of(scope) else ancestor)
		if target != null:
			target.grab_focus()
			return true
	return false


## 押せなくても（無効の釦でも）焦点を置ける。焦点の位置を保つための判定。
func _can_hold_focus(control: Control, scope: Control) -> bool:
	if not is_instance_valid(control) or control.is_queued_for_deletion():
		return false
	if not control.is_inside_tree() or not control.is_visible_in_tree():
		return false
	if control.get_focus_mode_with_override() != Control.FOCUS_ALL:
		return false
	return scope == null or control == scope or scope.is_ancestor_of(control)


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
