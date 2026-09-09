@tool
extends EditorPlugin

const AUTOLOAD_NAME := "GMornUI"


func _autoload_path() -> String:
	return get_script().resource_path.get_base_dir().path_join("gmorn_ui.gd")


func _enter_tree() -> void:
	# 既に登録済みなら足さない。毎回足すとエディタの起動ごとに「自動読み込みを追加」の
	# 履歴が（アドオンの数だけ）並ぶ。project.godot に書いてあれば、それで動く。
	if not ProjectSettings.has_setting("autoload/" + AUTOLOAD_NAME):
		add_autoload_singleton(AUTOLOAD_NAME, _autoload_path())


func _exit_tree() -> void:
	remove_autoload_singleton(AUTOLOAD_NAME)
