extends Node
## 親の Control をモーダルにする部品。シーンで親の子に置くだけで効く。
##
## 親が見えている間は、親の外の Control がマウス・タッチ・方向入力を受けなくなり、
## 開いた瞬間に中へ焦点が移り、閉じたら開く前の焦点へ戻る。重なれば最前面だけが操作を受ける。
## Unity の CanvasGroup（interactable / blocksRaycasts）を「最前面の1つだけ通す」形で束ねたもの。
## 中身は `GMornUI.register_modal()` と同じで、コードを書かずにシーンだけで決められる。
##
## キャンセル（`ui_cancel`）で閉じたいときは `cancelled` を受ける。受け手が無ければ
## キャンセルでは閉じない到達画面として扱い、`ui_cancel` は背面の処理へそのまま流れる。
## 受け手の有無は `_ready()` の時点で見るので、シーンでつなぐか、`_ready()` より前につなぐ。
##
## `class_name` は付けない（エディタが走査するまで引けず、取り込んだ直後の
## ヘッドレスで落ちる）。「ノードを追加」の GMornUIModal から置く。

signal cancelled

## 開いたときに焦点を置く Control。空なら中の押せる先頭へ置く。押せる物が無ければ置かない。
@export var initial: Control


func _ready() -> void:
	var scope := get_parent() as Control
	if scope == null:
		push_warning("GMornUIModal は Control の子に置く: %s" % get_path())
		return
	var service := get_node_or_null(^"/root/GMornUI")
	if service == null:
		push_warning("GMornUI が自動読み込みに無いので、%s はモーダルにならない" % scope.get_path())
		return
	var cancel := Callable()
	if not get_signal_connection_list(&"cancelled").is_empty():
		cancel = cancelled.emit
	service.register_modal(scope, initial, cancel)
