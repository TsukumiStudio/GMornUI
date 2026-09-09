@tool
extends EditorPlugin

const AUTOLOAD_NAME := "GMornUI"
const FONT_SIZE_TYPE := "GMornFontSize"
const FONT_SIZE := preload("gmorn_font_size.gd")


func _autoload_path() -> String:
	return get_script().resource_path.get_base_dir().path_join("gmorn_ui.gd")


func _enter_tree() -> void:
	_register_settings()
	add_custom_type(FONT_SIZE_TYPE, "Node", FONT_SIZE, null)
	# 既に登録済みなら足さない。毎回足すとエディタの起動ごとに「自動読み込みを追加」の
	# 履歴が（アドオンの数だけ）並ぶ。project.godot に書いてあれば、それで動く。
	if not ProjectSettings.has_setting("autoload/" + AUTOLOAD_NAME):
		add_autoload_singleton(AUTOLOAD_NAME, _autoload_path())


func _exit_tree() -> void:
	remove_custom_type(FONT_SIZE_TYPE)
	remove_autoload_singleton(AUTOLOAD_NAME)


## 「文字の大きさの段」の既定値をプロジェクト設定へ登録する（gmorn_ui/font_size/<段>）。
## 登録が無いと「プロジェクト設定」画面で戻す印が付き、どれを変えたのか分からない。
func _register_settings() -> void:
	for tier in FONT_SIZE.TIERS:
		var key: String = FONT_SIZE.PREFIX + tier
		var fallback: int = int(FONT_SIZE.DEFAULTS[tier])
		if not ProjectSettings.has_setting(key):
			ProjectSettings.set_setting(key, fallback)
		ProjectSettings.set_initial_value(key, fallback)
		ProjectSettings.add_property_info({
			"name": key, "type": TYPE_INT, "hint": PROPERTY_HINT_RANGE, "hint_string": "1,400,1",
		})
		ProjectSettings.set_as_basic(key, true)
