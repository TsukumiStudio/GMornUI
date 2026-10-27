@tool
extends EditorPlugin

const AUTOLOAD_NAME := "GMornUI"
const FONT_SIZE_TYPE := "GMornFontSize"
const FONT_SIZE := preload("gmorn_font_size.gd")
const MODAL_TYPE := "GMornUIModal"
const MODAL := preload("gmorn_ui_modal.gd")
const GMORN_UI := preload("gmorn_ui.gd")


func _autoload_path() -> String:
	return get_script().resource_path.get_base_dir().path_join("gmorn_ui.gd")


func _enter_tree() -> void:
	_register_settings()
	add_custom_type(FONT_SIZE_TYPE, "Node", FONT_SIZE, null)
	add_custom_type(MODAL_TYPE, "Node", MODAL, null)
	# 既に登録済みなら足さない。毎回足すとエディタの起動ごとに「自動読み込みを追加」の
	# 履歴が（アドオンの数だけ）並ぶ。project.godot に書いてあれば、それで動く。
	if not ProjectSettings.has_setting("autoload/" + AUTOLOAD_NAME):
		add_autoload_singleton(AUTOLOAD_NAME, _autoload_path())


func _exit_tree() -> void:
	remove_custom_type(FONT_SIZE_TYPE)
	remove_custom_type(MODAL_TYPE)
	remove_autoload_singleton(AUTOLOAD_NAME)


## 文字の大きさの組（gmorn_ui/font_sizes、{名前: px} の辞書）をプロジェクト設定へ登録する。
## 登録が無いと「プロジェクト設定」画面に出ず、戻す印も付く。中身は作品ごとに好きな数だけ書く。
func _register_settings() -> void:
	var key: String = FONT_SIZE.SETTING
	if not ProjectSettings.has_setting(key):
		ProjectSettings.set_setting(key, FONT_SIZE.DEFAULTS.duplicate())
	ProjectSettings.set_initial_value(key, FONT_SIZE.DEFAULTS.duplicate())
	ProjectSettings.add_property_info({"name": key, "type": TYPE_DICTIONARY})
	ProjectSettings.set_as_basic(key, true)
	# 方向の押し続け: 繰り返しに入るまでの秒数と、その後の間隔。
	for setting: Array in [
		[GMORN_UI.REPEAT_DELAY_SETTING, GMORN_UI.REPEAT_DELAY_DEFAULT],
		[GMORN_UI.REPEAT_INTERVAL_SETTING, GMORN_UI.REPEAT_INTERVAL_DEFAULT],
	]:
		if not ProjectSettings.has_setting(setting[0]):
			ProjectSettings.set_setting(setting[0], setting[1])
		ProjectSettings.set_initial_value(setting[0], setting[1])
		ProjectSettings.add_property_info({"name": setting[0], "type": TYPE_FLOAT,
			"hint": PROPERTY_HINT_RANGE, "hint_string": "0.01,2.0,0.01,suffix:s"})
		ProjectSettings.set_as_basic(setting[0], true)
