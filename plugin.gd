@tool
extends EditorPlugin

const AUTOLOAD_NAME := "GMornUI"


func _autoload_path() -> String:
	return get_script().resource_path.get_base_dir().path_join("gmorn_ui.gd")


func _enter_tree() -> void:
	add_autoload_singleton(AUTOLOAD_NAME, _autoload_path())


func _exit_tree() -> void:
	remove_autoload_singleton(AUTOLOAD_NAME)
