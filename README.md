# GMornUI

## Overview

画面とモーダルの入力範囲、初期焦点、Xキャンセル、閉じたあとの焦点復帰を一元管理するGodotアドオン。
モーダルを登録するだけで、表示中は最前面以外のControlをマウス・タッチ・方向入力から遮断する。

## Requirements

- Godot 4.5以降（4.7で確認）
- `ui_up` / `ui_down` / `ui_left` / `ui_right` / `ui_accept` / `ui_cancel` が設定済みであること。GMornInputとの併用を推奨する。

## Features

- 画面を開いたとき、指定した最初のControlへ焦点を置く。
- モーダルを開いたときだけ中へ焦点を移し、閉じたら開く前のControlへ戻す（画面を登録していなくても戻す）。
- 焦点の持ち主が作り直し・非表示・削除で消えたら、同じパスの作り直されたControl（無効の釦でも位置を保つ）、それも無ければ近い祖先の中の押せる先頭へ戻す。モーダルの裏で消えた焦点は閉じたときに同じ方法で戻す。`release_focus()` で意図して外した焦点（持ち主がまだ見えている）は戻さない。
- `GMornUIModal` を子に置くだけで、その Control をモーダルにできる（CanvasGroup のようにシーンで決める）。
- モーダル表示中は、暗幕の大きさや描画順に依存せず、背面のControlをマウス・タッチ・方向入力から遮断する。
- モーダルが重なっても最前面だけを操作でき、キャンセルも最前面だけへ渡す。
- 表示中に背面へ追加されたControlも自動で遮断し、閉じたら各Controlの元の入力設定へ戻す。
- ボタンのキーボード焦点は、共通 `.tres` の背景色と文字色へ反転し、Godot標準の白いfocus枠を重ねない。個別指定のfocus表示は維持する。
- 動的に作った一覧やキャラカードへ、同じ入口から焦点を置ける。
- 方向入力の行き先を中心の位置で決め、同じ行（上下なら同じ列）を優先する。矩形の端で比べる Godot の位置探しのように、数 px はみ出しただけの斜めの釦へ飛ばない。上下で行き先が無いときは画面上の読み順で折り返すので、どの配置でも全操作を辿れる。滑り棒・文字入力・一覧の矢印はその部品に任せる。
- 方向を押し続けたときは、`gmorn_ui/navigation_repeat_delay` 秒待ってから `gmorn_ui/navigation_repeat_interval` 秒ごとに送る（既定 0.4 / 0.12）。スティックは倒している間ずっと入力が届くので、間引かないと一瞬で端まで進む。鍵盤の繰り返しも OS の速さではなくこの間隔にそろえる。
- 焦点が無いときの決定／キャンセルを、画面全体の代替操作へ渡せる。
- 文字の大きさを名前で揃える（`GMornFontSize`。{名前: 大きさ} の組を `project.godot` に好きな数だけ）。

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

### 3b. シーンに置くだけでモーダルにする（GMornUIModal）

「ノードを追加」から `GMornUIModal` を、モーダルにしたい Control の子に置く。Unity の CanvasGroup で背面を止めるのと同じ使い方で、コードは要らない。

- `initial`: 開いたときに焦点を置く Control。空なら中の押せる先頭。
- `cancelled`: `ui_cancel` で届く。シーンでつないだときだけキャンセルで閉じる扱いになり、つながなければ `ui_cancel` は背面の処理へ流れる。

画面（`register_screen()`）を登録していない作品でも、閉じたら開く前の焦点へ戻る。

### 4. 動的な一覧へ焦点を置く

```gdscript
GMornUI.focus_first($CommandList)
```

`refresh_focus_chain()` は互換のために残しているが、もう配線はしない（呼ばなくてよい）。方向入力の行き先は `GMornUI.find_neighbor(control, side)` で引ける（検査で辿れるかを見るときに使う）。特定の隣へ行かせたいときだけ、釦の `focus_neighbor_*` に書く。

### 5. 文字の大きさを名前で揃える

大きさを画面ごとに数字で置くと、同じ役目の字が 44 と 46 のように少しずつ違ってくる。
作品ごとに {名前: 大きさ} の組を好きな数だけ登録し、ノード側は名前を選ぶだけにする。

1. `project.godot` の `gmorn_ui/font_sizes`（辞書）に組を書く（プロジェクト設定 → Gmorn Ui → Font Sizes でも編集できる）
2. 「ノードを追加」から `GMornFontSize` を、揃えたい Label / Button / RichTextLabel の子に置く
3. インスペクターの `preset` プルダウンから名前を選ぶ。エディタでもその場で大きさが変わる

```ini
[gmorn_ui]

font_sizes={
"body": 44,
"caption": 28,
"heading": 56
}
```

無い名前を選ぶと当てずに警告を出す（黙って別の大きさにならない）。
`GMornFontSize.size_of("body")` / `names()` で数や一覧を引ける。既定は `{"body": 16, "heading": 28}`。

### 6. 単独で確かめる

```sh
./verify.sh
```

一時の最小プロジェクトへアドオンを写し、背面クリックの遮断、動的追加、多重モーダル、焦点復帰を確かめる。

## License

Unlicense（パブリックドメイン）。
