# GMornUI

## Overview

画面とモーダルの入力範囲、初期焦点、Xキャンセル、閉じたあとの焦点復帰を一元管理するGodotアドオン。
モーダルを登録するだけで、表示中は最前面以外のControlをマウス・タッチ・方向入力から遮断する。

## Requirements

- Godot 4.5以降（4.7で確認）
- `ui_up` / `ui_down` / `ui_left` / `ui_right` / `ui_accept` / `ui_cancel` が設定済みであること。GMornInputとの併用を推奨する。

## Features

- 画面を開いたとき、指定した最初のControlへ焦点を置く。
- モーダルを開いたときだけ中へ焦点を移し、閉じたら開く前のControlへ戻す。
- モーダル表示中は、暗幕の大きさや描画順に依存せず、背面のControlをマウス・タッチ・方向入力から遮断する。
- モーダルが重なっても最前面だけを操作でき、キャンセルも最前面だけへ渡す。
- 表示中に背面へ追加されたControlも自動で遮断し、閉じたら各Controlの元の入力設定へ戻す。
- ボタンのキーボード焦点は、共通 `.tres` の背景色と文字色へ反転し、Godot標準の白いfocus枠を重ねない。個別指定のfocus表示は維持する。
- 動的に作った一覧やキャラカードへ、同じ入口から焦点を置ける。
- 表示中の全操作を画面上の順に上下へつなぎ、方向入力だけで必ず一周できる。
- 焦点が無いときの決定／キャンセルを、画面全体の代替操作へ渡せる。
- 文字の大きさを「段」の名前で揃える（`GMornFontSize`。数は `project.godot` の1か所）。

## Usage

### 1. 取り込む

アドオン一式を `addons/gmorn_ui` へ置き、Godotの「プロジェクト設定 → プラグイン」から `GMornUI` を有効にする。自動読み込みへ `GMornUI` が登録される。

リポジトリ直下に `project.godot` は置かない。別のGodotプロジェクトと判定され、submoduleとして取り込んだとき書き出しから除外されるためである。

### 2. 通常画面を登録する

```gdscript
func _ready() -> void:
    GMornUI.register_screen(self, $Menu/Start, _cancel, _advance)
```

初期焦点を置きたくない画面では第2引数を `null` にする。方向入力が来たときだけ、押せる先頭へ焦点が入る。

登録済み画面と、あとからSceneTreeへ追加したButtonは、focus表示を個別指定していない場合だけ `button_focus_theme.tres` の背景色・枠色・文字色へ切り替わる。色はこの `.tres` の1か所で変更でき、角丸と余白は各Buttonのnormalから引き継ぐ。白い枠を上から重ねるだけの表示には戻さない。

Buttonではない独自Controlを操作に使う場合も、`make_button_focus_style()` と `button_focus_text_color()` で同じ色を利用できる。

### 3. モーダルを登録する

```gdscript
func _ready() -> void:
    GMornUI.register_modal(self, $Panel/Close, _close)
```

表示／非表示を監視するため、`visible = true` と `visible = false` だけで焦点の移動と復帰が働く。Xで閉じてはいけない画面はキャンセルを省略する。

入力遮断用の透明パネルや、背面ボタンごとの `disabled` 切り替えは不要である。最前面モーダルの子孫だけが入力可能になり、閉じると開く前の `mouse_behavior_recursive` / `focus_behavior_recursive` が復元される。この2プロパティはモーダル表示中だけGMornUIが管理する。

### 4. 動的な一覧へ焦点を置く

```gdscript
GMornUI.focus_first($CommandList)
```

一覧を作り直した画面では、全操作を方向入力で巡回できるよう焦点チェーンも更新する。

```gdscript
GMornUI.refresh_focus_chain(self)
```

### 5. 文字の大きさを「段」で揃える

大きさを画面ごとに数字で置くと、同じ役目の字が 44 と 46 のように少しずつ違ってくる。
段の名前（caption / small / body / large / heading / display）で指し、実際の大きさは
`project.godot` の1か所で決める。

1. 「ノードを追加」から `GMornFontSize` を、揃えたい Label / Button / RichTextLabel の子に置く
2. インスペクターで `tier` を選ぶ。エディタでもその場で大きさが変わる
3. 作品の大きさは `project.godot` に書く（プロジェクト設定 → Gmorn Ui → Font Size にも出る）

```ini
[gmorn_ui]

font_size/caption=28
font_size/small=36
font_size/body=44
font_size/large=52
font_size/heading=60
font_size/display=120
```

既定は 12 / 14 / 16 / 20 / 28 / 40。`GMornFontSize.size_of("body")` で数を引くこともできる。

### 6. 単独で確かめる

```sh
./verify.sh
```

一時の最小プロジェクトへアドオンを写し、背面クリックの遮断、動的追加、多重モーダル、焦点復帰を確かめる。

## License

Unlicense（パブリックドメイン）。
