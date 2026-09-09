@tool
extends Node
## 親の Control に「文字の大きさの段」を当てる。
##
## 文字の大きさを画面ごとに数字で置くと、同じ役目の字が画面によって 44 と 46 の
## ように少しずつ違ってくる。段（caption / small / body / large / heading / display）
## の名前で指し、実際の大きさは `project.godot` の `gmorn_ui/font_size/<段>` に
## 作品ごとに1か所で決める。
##
## 使い方: 大きさを揃えたい Label や Button の子にこのノードを置き、`tier` を選ぶ。
## エディタでも効く（`@tool`）ので、シーンの見た目がそのまま揃う。
##
## `class_name` は付けない（エディタが走査するまで引けず、取り込んだ直後の
## ヘッドレスで落ちる）。「ノードを追加」の GMornFontSize から置く。

const PREFIX := "gmorn_ui/font_size/"
const TIERS: PackedStringArray = ["caption", "small", "body", "large", "heading", "display"]
const DEFAULTS := {
	"caption": 12, "small": 14, "body": 16, "large": 20, "heading": 28, "display": 40,
}

## どの段か。名前は `TIERS` のどれか。
@export_enum("caption", "small", "body", "large", "heading", "display") var tier := "body":
	set(value):
		tier = value
		apply()

func _ready() -> void:
	apply()

## 段の大きさ（px）。設定に無ければ既定。
static func size_of(tier_name: String) -> int:
	var fallback: int = int(DEFAULTS.get(tier_name, DEFAULTS["body"]))
	return int(ProjectSettings.get_setting(PREFIX + tier_name, fallback))

## 親へ当てる。親が Control でなければ何もしない。
func apply() -> void:
	var target := get_parent() as Control
	if target == null:
		return
	var size := size_of(tier)
	# RichTextLabel は normal/bold/italic が別々。まとめて同じ段にする。
	if target is RichTextLabel:
		for key in ["normal_font_size", "bold_font_size", "italics_font_size", "bold_italics_font_size"]:
			target.add_theme_font_size_override(key, size)
		return
	target.add_theme_font_size_override("font_size", size)
