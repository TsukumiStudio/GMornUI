@tool
extends Node
## 親の Control に、名前で登録した文字の大きさを当てる。
##
## 文字の大きさを画面ごとに数字で置くと、同じ役目の字が画面によって 44 と 46 の
## ように少しずつ違ってくる。作品ごとに {名前: 大きさ} の組を `project.godot` の
## `gmorn_ui/font_sizes`（辞書）に好きな数だけ登録し、ノード側は名前を選ぶだけにする。
##
## 使い方: 大きさを揃えたい Label や Button の子にこのノードを置き、`preset` を
## プルダウンから選ぶ。エディタでも効く（`@tool`）ので、シーンの見た目がそのまま揃う。
##
## `class_name` は付けない（エディタが走査するまで引けず、取り込んだ直後の
## ヘッドレスで落ちる）。「ノードを追加」の GMornFontSize から置く。

const SETTING := "gmorn_ui/font_sizes"
## 何も登録していないときの組。作品側で `project.godot` に書けば丸ごと置き換わる。
const DEFAULTS := {"body": 16, "heading": 28}

## 登録した名前のどれか。一覧は `gmorn_ui/font_sizes` の鍵から作る。
@export var preset := "":
	set(value):
		preset = value
		apply()

func _ready() -> void:
	apply()
	if Engine.is_editor_hint():
		ProjectSettings.settings_changed.connect(apply)

## インスペクターの `preset` を、登録済みの名前のプルダウンにする。
func _validate_property(property: Dictionary) -> void:
	if property.name == "preset":
		property.hint = PROPERTY_HINT_ENUM
		property.hint_string = ",".join(names())

## 登録した組。設定に無ければ既定。
static func presets() -> Dictionary:
	var value: Variant = ProjectSettings.get_setting(SETTING, DEFAULTS)
	return value if value is Dictionary and not (value as Dictionary).is_empty() else DEFAULTS

## 登録した名前（登録順）。
static func names() -> PackedStringArray:
	var result: PackedStringArray = []
	for key in presets():
		result.append(String(key))
	return result

## 名前の大きさ（px）。無い名前なら 0。
static func size_of(preset_name: String) -> int:
	return int(presets().get(preset_name, 0))

## 親へ当てる。親が Control でない、または名前が無ければ何もしない
## （無い名前は黙って素通りせず、エディタで声を上げる）。
func apply() -> void:
	var target := get_parent() as Control
	if target == null or preset.is_empty():
		return
	var size := size_of(preset)
	if size <= 0:
		push_warning("GMornFontSize: 「%s」は gmorn_ui/font_sizes に無い（%s）" % [preset, get_path()])
		return
	# RichTextLabel は normal/bold/italic が別々。まとめて同じ大きさにする。
	if target is RichTextLabel:
		for key in ["normal_font_size", "bold_font_size", "italics_font_size", "bold_italics_font_size"]:
			target.add_theme_font_size_override(key, size)
		return
	target.add_theme_font_size_override("font_size", size)
