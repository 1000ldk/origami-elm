# origami-elm

Elm のコードベースを読み込み、その構造を **Lang の tree method**（TreeMaker の stick figure）の
入力木に変換して、**幾何的に検証した**折り紙の展開図を生成する CLI。

全体 **Swift**（`Sources/*.swift`、外部依存なし・Foundation のみ）。

---

## セットアップ

### 1. Swift を用意する

依存は Swift 5.7 以降と Foundation だけ。パッケージは一切使いません。

**macOS** — Xcode が入っていれば済んでいます。入っていなければ:

```sh
xcode-select --install     # Command Line Tools だけでも可
swift --version            # 5.7 以上なら OK
```

**Linux (Ubuntu / Fedora など)** — 公式 toolchain を入れます:

```sh
curl -sL https://swiftlang.github.io/swiftly/swiftly-install.sh | bash
swiftly install latest
swift --version
```

（`swiftly` が使えない環境なら <https://www.swift.org/install/linux/> から tarball を落として
`/opt/swift` に展開し、`export PATH=/opt/swift/usr/bin:$PATH` でも動きます。）

**Windows** — WSL2 上で Linux の手順を使うのが確実です。

### 2. 取得してビルド

```sh
git clone https://github.com/1000ldk/origami-elm
cd origami-elm
make                       # -> bin/origami
```

SwiftPM を使いたい場合はこちらでも同じものができます:

```sh
swift build -c release     # -> .build/release/origami
```

### 3. ビルドが正しいことを確認する

同梱の4葉サンプルは、**検証済みの展開図が必ず出る**ことが分かっているケースです。

```sh
make check
# => OK: verified crease pattern emitted for examples/star4
```

これが通れば、ソルバも幾何の検証器も正しく動いています。

### 4. 自分のリポジトリを読ませる

```sh
./bin/origami ~/dev/my-elm-app -o out        # ローカルのディレクトリ
./bin/origami 1000ldk/elm-web -o out         # GitHub の owner/repo（clone して解析、終了時に破棄）
./bin/origami https://github.com/... -o out  # 任意の git URL
open out/report.md out/packing.svg           # Linux なら xdg-open
```

`git` は `owner/repo` や URL を渡したときだけ必要です（ローカルディレクトリなら不要）。
ネットワークアクセスもそのときだけです。

### トラブルシューティング

| 症状 | 対処 |
|---|---|
| `no .elm files found under ...` | `src/` ではなくリポジトリのルートを渡していないか確認。`elm-stuff/` と `tests/` は除外されます |
| `could not determine a root module` | `Main` が無いリポジトリです。`--root MyEntryModule` で指定してください |
| `cannot resolve source: ...` | `git clone` に失敗しています。private リポジトリなら先に自分で clone してローカルパスを渡してください |
| 実行が遅い | 既定は `--restarts 250`。試行錯誤中は `--restarts 40` で十分です |

---

## 使い方

```sh
./bin/origami <source> [options]
```

`<source>` はローカルディレクトリ / git URL / `owner/repo`。git URL の場合は
`git clone --depth 1` して解析し、終了時に破棄します（`--keep-clone` で保持）。

```sh
./bin/origami ./my-elm-app -o out
./bin/origami 1000ldk/elm-web -o out --granularity view
```

主なオプション（`--help` に全部あります）:

| オプション | 意味 |
|---|---|
| `--granularity view\|module` | `view`（既定）= Html を返す宣言ごとに1フラップ / `module` = モジュールごとに1フラップ |
| `--shared duplicate\|hinge` | 複数の親から import されるモジュールの木化方針 |
| `--drop-unused-imports` | 本文に参照がない import を無視する |
| `--uniform` | 枝長をコード量ではなく一律 1 にする |
| `--root MODULE` | エントリモジュールを指定（既定: `Main`、なければ推定） |
| `--corner-flaps` | 紙の4隅にフラップを追加する（木を変える設計判断。スケールは下がる） |
| `--paper MM` | mm 換算に使う紙の一辺（既定 150） |

## パイプライン

```
Elm sources
  → module / import / 型注釈の走査            ElmParse.swift
  → 依存グラフ → 単一根の重み付き木           TreeBuild.swift
  → Lang の tree theorem（スケール最大化）     Packing.swift
  → active path の平面分割 → 分子             Molecule.swift
  → 川崎 / 前川 / crimp による全頂点検証       Origami.swift
  → SVG                                       SVG.swift
```

**手作業だった部分はすべて自動化済み**です。以前のバージョンではリポジトリ固有のノード名を
`main.swift` に直書きしていましたが、現在は木の抽出まで含めて機械的に行います。

- 根 = `Main`（なければ到達数最大のモジュール）
- 葉 = 木で子を持たないノード。`--granularity view` では、型注釈の戻り値が `Html` /
  `Browser.Document` である**トップレベル宣言**を葉として切り出す（判定は型注釈のみに基づく）
- 枝長 = そのノードに帰属するコード行数 / 10（下限 0.5）。複製されたモジュールは行数を複製数で割る
- 共有モジュール（複数の親から import される）は既定で**複製**。木が爆発する場合は自動的に
  `hinge`（最短経路の親だけを残す）にフォールバックし、その旨を出力に書く

## 検証していること / していないこと

**幾何的に検証している**

- Lang の距離条件 `‖u_i − u_j‖ ≥ m · d_T(i,j)` を全ペアで再評価（min slack を出力）
- スケール `m` の最大化。既知の最適点配置 8 ケース（n=2〜9）で求解器を検証済み（誤差 0）
- 川崎定理（交互和 = 0）を全内部頂点で計算
- 前川定理（|M−V| = 2）を全内部頂点で計算
- M/V 割り当ての平坦折り可能性を crimp 簡約で判定。判定器は degree-4 の教科書解と一致することを
  自己テスト済み。奇数次数の頂点は「平坦折り不可能」として明示的に弾く

**検証していない**

- 層の重なり順（多頂点の展開図の平坦折り可能性判定は NP 困難）。ここでの根拠は
  Universal Molecule 定理と上記の頂点ごとの条件

**比喩（人間が決めた対応付け。数学的根拠はない）**

- 「Html を返す宣言 = 角（フラップ）」という対応
- 「枝の長さ = コード行数 / 10」という対応（単調写像であればよい、という以上の根拠はない）
- 相互排他なルート（`Home` と `About` は同時に描画されない）を、同時に存在する角として扱っている

## 出力

`out/report.md` に全計算結果、加えて:

- `packing.svg` — 円配置図。**展開図ではない**（図中にもそう明記）
- `crease-pattern.svg` — 全面が分子で埋まり、全内部頂点が3条件を通ったときだけ出力
- `molecules-partial.svg` — 部分的にしか埋まらなかった場合。**折れる展開図ではない**旨をタイトルに明記

検証を通らない展開図は出しません。通らなかった場合は「どの面が、なぜ埋まらなかったか」を面ごとに出力します。

## 現状の到達点

**動く例**（4葉の星型 → square molecule = 4フラップ基本形）:

```
- faces filled with a molecule: 1 / 1  (area coverage 100.0%)
- Kawasaki at every interior vertex: SATISFIED (worst |alternating sum| = 0.000000000 degrees)
- Maekawa at every interior vertex: SATISFIED
- single-vertex flat-foldability (crimp reduction): FOLDABLE
→ Verified crease pattern emitted
```

**まだ展開図が出ない例**（`1000ldk/elm-web`、view 粒度、12葉）:

```
- certified scale m = 0.102140   (min slack 0.000000000、全点が正方形内)
- binding (active) constraints: 11
- faces of the active-path subdivision: 5
- faces filled with a molecule: 0 / 5
  → 4面: 紙の隅が葉ノードに占有されていない
  → 1面: 内接円を持たない多角形（gusset 分子が必要）
```

ここまでで、**円配置とその検証・木の抽出は任意の Elm リポジトリで動きます**。
展開図が出るかどうかは、下の2点にかかっています。

## 残っている実装（ここが本丸）

1. **一般の universal molecule（gusset 分子 / river 分子）**
   現在は「内接円を持つ多角形」の分子しか生成できません。三角形（rabbit ear）と正方形は
   これに含まれますが、一般の四角形以上は内接円を持たないので gusset が要ります。
   Lang の inset アルゴリズム（contraction event と splitting event を扱うイベント駆動の
   straight-skeleton 的計算）の実装が必要です。

2. **紙の隅の扱い**
   最適配置では隅が葉ノードに占有されないことが多く、その領域を吸収するフラップがありません。
   `--corner-flaps` で隅にフラップを追加できますが、これは木を変える設計判断です。
   TreeMaker と同じく「隅を使う配置を優先する」項を最適化に入れるほうが筋が良いはずです。

3. （副次的）**配置の剛性化**
   スケール最大化だけでは配置が拘束不足で、active path が疎になり面が大きくなりすぎます。
   `--compact` を試しましたが binding constraints は増えませんでした（既定オフ、実験扱い）。
   本来は辞書式最大化（最小比を固定して次の最小比を最大化、を繰り返す）が必要です。

## その他の限界

- **`m` は下界であって最適値の証明ではない。** 返す配置は全制約を再評価して検証済みなので
  「その `m` で折れる」ことは確実ですが、非凸問題なので大域最適性は主張しません
  （TreeMaker 自身も同じ立場）。既知最適 8 ケースの再現が信頼度の根拠です。
- **葉の切り出しは型注釈のみに依存。** 型注釈のない宣言は葉になりません。`case` の分岐単位まで
  分けるには実際の AST 解析が必要です（現状は行指向スキャナ）。
- **Elm 専用。** 主要言語への拡張は、`ElmParse` を言語ごとの import 抽出に差し替える形で行う予定。
  木の抽出（`TreeBuild`）以降は言語非依存です。
- 外部パッケージの依存は解析対象外（`elm.json` を読んでいない）。

## `1000ldk/elm-web` を読ませて出てきたコード側の指摘

- `Api/Endpoint.elm` の `import Article.slug` は小文字始まりで `Article.Slug` に解決されない。
  このファイルはコンパイルできない（`request` に本体がなく `url` も未定義）。
- `Main` が `main.elm` にある（Elm は `Main.elm` を要求）。
- `Api.Endpoint` / `Article.Slug` / `Article.Articles.R8.ElmBlog` は `Main` から到達不能。
- `Page/About.elm:8` の `import Route exposing (Route(..))` は本文で一度も使われていない
  （`Route(..)` を `Route.elm` の constructor 定義まで展開したうえでトークン走査した結果）。
