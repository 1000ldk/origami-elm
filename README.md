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
# => ok   rabbit ear (equilateral triangle): 6 creases
# => ok   square molecule (star4): 8 creases
# => ok   river quad must be refused: refused as expected — ...
# => ok   non-tangential quad, contraction only: ...
# => all self-tests passed
# => OK: verified crease pattern emitted for examples/star4
```

これが通れば、ソルバも幾何の検証器も分子生成器も正しく動いています。
自己テストだけを走らせるなら `./bin/origami --self-test`（リポジトリ不要）。
既知解のケース（rabbit ear / square molecule / 内接円を持たない四角形）に加えて、
**gusset が必要な面がきちんと「拒否」されること**も検査しています。

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
| `--corners auto\|flaps\|none` | 紙の隅の扱い（既定 `auto`）。下記参照 |
| `--corner-keep F` | 隅スナップを採用する最低スケール比（既定 0.98） |
| `--corner-flap-length L` | 隅フラップ長の上限。実際に使う長さは「スケールを一切下げない最大値」 |
| `--paper MM` | mm 換算に使う紙の一辺（既定 150） |

## パイプライン

```
Elm sources
  → module / import / 型注釈の走査            ElmParse.swift
  → 依存グラフ → 単一根の重み付き木           TreeBuild.swift
  → Lang の tree theorem（スケール最大化）     Packing.swift
  → 隅の占有（バイアス→スナップ→安全な隅フラップ）Packing.swift / main.swift
  → active path の平面分割 → axial polygon     Molecule.swift
  → universal molecule（inset アルゴリズム）   UniversalMolecule.swift
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
- 川崎定理（交互和 = 0）を全内部頂点で計算。**ただし全面が埋まったときだけ**。
  面が残っていると、隣の分子が来ないまま hinge の足が axial crease に落ちて次数が奇数になり、
  幾何とは無関係な「川崎違反」が出るためです。未完成の分解ではその旨だけを報告します
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

ここまでで、**円配置とその検証・木の抽出は任意の Elm リポジトリで動きます**。

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

イベントは2種類:

- **contraction**: 辺が長さ 0 になる。隣接2頂点が併合し、その合流点から、消えた辺の
  *元の* 線分（生まれたときの高さの線分）へ垂線を下ろしたものが hinge crease になります。
  一様 inset なので、共有辺の両側から下ろした足は**構成上必ず一致します**。
- **splitting（gusset / river）**: 非隣接対が `|p_i − p_j| = R_ij` に達する。**検出はして
  いますが、埋めずに理由付きで拒否します。** 多角形を2つの部分多角形に分けて独立に処理する
  素朴な実装は誤りで、両側の部分分子が新しい辺（gusset）の**異なる点**に hinge を下ろします
  （それぞれ木の別の分岐ノードに対応するため）。結果として次数が奇数の頂点ができ、平坦に
  折れません。正しくは river を帯として扱う必要があり、それは未実装です。

三角形は1イベントで内心に潰れて rabbit ear に、正方形は中心に潰れて `Origami.squareMolecule`
に一致します。つまりこの実装は、置き換えた「内接円を持つ多角形」の分子を**真に含みます**:
内接円を持たない多角形でも、contraction だけで木と整合的に還元できるものは埋まります。

## 残っている実装

1. **river（gusset）分子**
   splitting event は正確に検出して「どの inset で、どの頂点対で起きるか」を報告しますが、
   その面は埋めません。river を帯として扱う実装が必要です。

2. （副次的）**配置の剛性化**
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
