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
# => ok   degree-4 crimp test: 8/8 assignments accepted (M=1:4, M=3:4)
# => ok   rabbit ear (equilateral triangle): 6 creases, 1 interior vertices, M/V found
# => ok   square molecule (star4): 8 creases, 1 interior vertices, M/V found
# => ok   gusset with a river along it: 29 creases, 14 interior vertices, M/V found
# => ok   non-tangential quad, contraction only: ...
# => ok   river rectangle (r = 1.000000): 7 creases, 2 interior vertices, M/V found
# => all self-tests passed
# => OK: verified crease pattern emitted for examples/star4
```

これが通れば、ソルバも幾何の検証器も分子生成器も正しく動いています。
自己テストだけを走らせるなら `./bin/origami --self-test`（リポジトリ不要）。
既知解のケース（rabbit ear / square molecule / 内接円を持たない四角形）に加えて、
**river（川）を含む面** — gusset に沿って river が走る四角形と、線分に潰れる
古典的な gusset 分子（長方形）— も検査します。各ケースは「幾何が通る」だけでなく、
**全内部頂点で Maekawa と crimp を通す M/V 割り当てが存在すること**まで確認します。

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
| `--lengths code\|uniform\|log` | コード量→枝長の写像（既定 `code` = 行数/10）。下記参照 |
| `--uniform` | `--lengths uniform` の別名 |
| `--root MODULE` | エントリモジュールを指定（既定: `Main`、なければ推定） |
| `--corners auto\|flaps\|none` | 紙の隅の扱い（既定 `auto`）。下記参照 |
| `--corner-keep F` | 隅スナップを採用する最低スケール比（既定 0.98） |
| `--corner-flap-length L` | 隅フラップ長の上限。実際に使う長さは「スケールを一切下げない最大値」 |
| `--no-rigid` | 配置の剛性化（辞書式最大化）を止める。既定は有効。下記参照 |
| `--paper MM` | mm 換算に使う紙の一辺（既定 150） |

## パイプライン

```
Elm sources
  → module / import / 型注釈の走査            ElmParse.swift
  → 依存グラフ → 単一根の重み付き木           TreeBuild.swift
  → Lang の tree theorem（スケール最大化）     Packing.swift
  → 隅の占有（バイアス→スナップ→安全な隅フラップ）Packing.swift / main.swift
  → 配置の剛性化（辞書式最大化）               Packing.swift
  → active path の平面分割 → axial polygon     Molecule.swift
  → universal molecule（inset + river）        UniversalMolecule.swift
  → 面をまたぐ river ノードの受け渡し           Molecule.swift
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

## 枝長の決め方（`--lengths`）

写像は単調でありさえすればよく、幾何側はどれでも構いません。ただし**選び方で使い物になるか
どうかが決まります**。

既定の `code`（行数/10）は生の比をそのまま持ち込みます。120行のモジュールと7行の view が
同居すると枝長は 12.0 対 0.7 になり、**大きいほうのフラップの円が紙より大きくなって**
（半径 1.24 > 1）他のフラップが隅に押し込められ、隅フラップを足す余地も無くなります
（`L ≤ |u_j − c|/m − d_T(root, j)` が負になる）。

`log`（`log2(1 + 行数) / 2`）は順序を保ったまま範囲を圧縮します。同じ例で 3.46 対 1.50、
比は 17 倍から 2.3 倍に下がり、正方形が実際に収められる配置になります。
`uniform` は全部 1 で、構造だけを見る一番強い圧縮です。

**フラップの円が紙からはみ出している（`flap length (unit square)` が 1 を超えている）ときは、
まず `--lengths log` を試してください。**

## 紙の隅の扱い（`--corners`）

隅を占有する葉がないと、その隅を含む面は axial polygon ではなく、分子が存在しません。
既定の `auto` は次の順で試します。

1. **配置バイアス** — 勾配上昇の目的関数に「各隅に最も近い葉を隅へ引く」項を、
   焼きなましで 0 に落としながら加えます。認定スケールは最後に全制約を再評価して
   求め直すので、**この項が `m` の正しさに影響することはありません**（探索の誘導のみ）。
2. **スナップ** — 各隅について最寄りの葉を隅に固定し、再射影します。スケールが
   `--corner-keep`（既定 0.98）を割らないときだけ採用します。木は変えません。
3. **安全な隅フラップ** — それでも空いた隅にだけフラップを足します。長さは
   **スケールを一切下げない最大値**

   ```
   L ≤ |u_j − c| / m − d_T(root, j)   （既存の全ての葉 j と隅 c について）
   L ≤ |c − c'| / (2m)                （隅フラップ同士）
   ```

   を計算して使います。`L ≤ 0` なら「無料では足せない」と報告して**足しません**。

旧 `--corner-flaps` は長さに「既存の最短葉辺」を使っていました。これは実行可能性と
無関係な値で、隣接する隅同士の制約 `m ≤ 1/(2L)` が binding になってスケールを引き下げ、
実際の葉の間の active path を痩せさせていました。現在 `--corner-flaps` は
`--corners flaps` の別名で、長さは上の安全な値を使います。

## 検証していること / していないこと

**幾何的に検証している**

- Lang の距離条件 `‖u_i − u_j‖ ≥ m · d_T(i,j)` を全ペアで再評価（min slack を出力）
- スケール `m` の最大化。既知の最適点配置 8 ケース（n=2〜9）で求解器を検証済み（誤差 0）
- 面が axial polygon であること（全辺が active path で長さがちょうど `m · d_T`、対角線が
  `≥ m · d_T`）を、分子を作る前に全面で検査。ここを通らない面は理由付きで未充填にします
- 分子の inset の不変量 `|p_i − p_j| = R_ij`（隣接対）を再帰の各段で再検査
- 分子を返す前に、**その面の内部頂点をすべて**検査（偶数次数と川崎）。通らない面は
  埋めずに理由を出します。river を持ち込む処理が正しく効いたかどうかは、ここで決まります
- gusset の両側が、共有する path の**同じ点**に折り線を落とすこと（合意するまで反復）
- 川崎定理（交互和 = 0）を全内部頂点で計算。**ただし全面が埋まったときだけ**。
  面が残っていると、隣の分子が来ないまま hinge の足が axial crease に落ちて次数が奇数になり、
  幾何とは無関係な「川崎違反」が出るためです。未完成の分解ではその旨だけを報告します
- 前川定理（|M−V| = 2）を全内部頂点で計算
- M/V 割り当ての平坦折り可能性を crimp 簡約で判定。判定器は degree-4 の教科書解と一致することを
  自己テスト済み。奇数次数の頂点は「平坦折り不可能」として明示的に弾く
- 自己テストの各分子は、**全内部頂点で前川と crimp を通す M/V 割り当てが実在すること**まで
  確認します（`--self-test`）

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

**river を含む例**（gusset に沿って river が走る四角形、`--self-test` のケース）:

```
- gusset with a river along it: 29 creases, 14 interior vertices, M/V found
```

以前は同じ面が「両側の hinge が別の点に落ちる」として拒否されていたものです。

ここまでで、**円配置とその検証・木の抽出は任意の Elm リポジトリで動きます**。
分子側は、river を含む面（gusset に river が走る面・線分に潰れる面）も埋まるようになり、
面をまたぐ river も受け渡します。残る主な障害は紙の隅と紙の縁です。

## 分子の作り方（`UniversalMolecule.swift`）

**axial polygon** = 全ての辺が active path である面。辺 (i, i+1) の長さがちょうど
`m · d_T(node_i, node_j)` で、対角線が `≥ m · d_T` を満たすもの。これを inset して埋めます。

多角形を t だけ inset すると、頂点 i は角の二等分方向 `b_i`（`b_i · n_{i-1} = b_i · n_i = 1`）
に沿って動きます。`c_i = b_i · e_i = cot(α_i / 2)` と置くと、折った形での高さ t の点までの
紙上距離が `t / sin(α_i/2)` であることから

```
m · δ_i(t) = t · cot(α_i / 2) = t · c_i
```

つまり **頂点 i は inset 1 あたり `c_i / m` の木長を消費する**。したがって必要距離は線形に減り

```
R_ij(t) = R_ij(0) − t · (c_i + c_j)
```

一方、辺のオフセット長は正確に `c_i + c_{i+1}` の速さで縮むので、隣接対については
`|p_i(t) − p_j(t)| = R_ij(t)` が**恒等的に保たれます**。これが本アルゴリズムの不変量で、
再帰の各段の冒頭で再検査しています。

イベントは3種類:

- **contraction**: 辺が長さ 0 になる。隣接2頂点が併合し、その合流点から、消えた辺の
  *元の* 線分（生まれたときの高さの線分）へ垂線を下ろしたものが hinge crease になります。
  一様 inset なので、共有辺の両側から下ろした足は**構成上必ず一致します**。
- **splitting（gusset）**: 非隣接対が `|p_i − p_j| = R_ij` に達する。その path が active に
  なるので、多角形をそこで2つに切り、それぞれを（高さ `t` の axial polygon として）再帰で
  処理します。
- **degenerate**: 縮小多角形が線分に潰れる。残っているのは active path そのもの、つまり
  **river** で、それが折り線になって面は完成します。これが古典的な gusset 分子です
  （短辺が2つの分岐ノードのフラップである長方形は、ちょうどこの形に潰れます）。

## river（川）の扱い

**river** は分岐ノード同士を結ぶ木の辺です。gusset で2つに切った両側は、自分の頂点が
path のどこで合流するかしか知りません。gusset に沿って river が走ると、
**両側が別々の点に hinge を下ろし**、共有する path に相方のない折り線 —
すなわち平坦折り不可能な奇数次数の頂点 — ができます。以前のバージョンが
「river 分子は未実装」として面ごと拒否していたのはこれです。

解決は **river をそのまま持ち込むこと**です。gusset 上の分岐ノードを、反対側の多角形に
**共線の頂点**として挿入します。その頂点の内角は 180° なので

- `c = cot(90°) = 0` — 木長を消費しません。river のノードは縮むフラップではなく
  木の固定点なので、これが正しい挙動です
- inset ではその頂点は gusset に垂直にまっすぐ進む — それがそのノードの**等高線**であり、
  相方として足りなかった折り線そのものです

どのノードが必要かは木から初期値を作り（反対側の各頂点の合流点）、そのあと
**両側が gusset 上の同じ点に折り線を落とすまで反復**して確定させます。

同じノードは「消費される側」でも要ります。フラップがちょうど river ノードで尽きる瞬間、
そのノードの等高線は ridge で折れ曲がって隣の領域へ続きます（その領域の axial 基線に垂直）。
この腕がないと合流点が奇数次数になります。

river は面もまたぎます。面を横切った river は、その面の境界上に等高線の足を残しますが、
向かい側の面はそのノードを知りません（自分の頂点が合流する所でしか分岐しない）。そこで
`Molecule.build` は、**片側だけが折り線を落とした点を反対側の面に `UM.withNode` で
共線頂点として渡し**、分子を作り直します（これも反復。渡したノードが新しい折り線を
生むことがあるため）。

三角形は1イベントで内心に潰れて rabbit ear に、正方形は中心に潰れて `Origami.squareMolecule`
に一致します。つまりこの実装は、置き換えた「内接円を持つ多角形」の分子を**真に含みます**:
内接円を持たない多角形も、river が走る面も埋まります。

## 配置の剛性化（`--no-rigid` で無効化）

スケール最大化は `m` で binding になる対しか固定しません。残りは緩んだままなので、
active path が疎になり、平面分割の面が大きくなりすぎ、分子の作りようがない面が残ります。

そこで `m` を認定したあと、**辞書式最大化**を行います。

1. binding な対を、いまいる高さに**そのまま固定**する（≥ ではなく = で保持。
   でないと active path が緩んで消えてしまいます）
2. 接触まであと `1%` 以内の対を**接触まで引き寄せる**。ニアミスは、ソルバが閉じ損ねた
   active path です。射影が収束し、かつスケールが落ちないときだけ採用します
3. まだ自由な対のうち**最小の比を最大化**し、binding になったものを固定して 1 に戻る

固定された対は自分の高さで保たれ、スケールが下がる変更は一切採用しないので、
**`m` は決して下がりません**（返り値は例によって全制約を再評価して検証します）。
合成した木での実測では、12葉で active path が 11 → 15、8葉で 6 → 9 に増えました
（いずれも `m` は不変）。既に剛な配置では何も起きません。

以前の `--compact`（全ての緩んだ対を一律に引き寄せる実験）は binding constraints を
増やさなかったため、これに置き換えて削除しました。

## 残っている実装

- **紙の隅と紙の縁**。隅を占有する葉がない面、および辺の一部が紙の縁である面には
  分子が存在しません（`--corners` で緩和はしますが、無料で足せる隅フラップが無い場合は
  そのまま未充填になります）。実リポジトリで面が埋まらない主因はいまここです。
- **gusset の合意反復には上限があります**（面内 6 回、面をまたいで 4 回）。到達しない
  場合はその面を埋めずに理由を出します。乱択試験では発生していませんが、収束の証明は
  していません。

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
