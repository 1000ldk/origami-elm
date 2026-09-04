# origami-elm

`1000ldk/elm-web`（Elm製の個人ブログ）のコード構造を **Lang の tree method**（TreeMaker の
stick figure）の入力木に変換し、**幾何的に検証したうえで**「実現可能な角（フラップ）」と
展開図を出力する解析器。

解析器はすべて **Swift**（`Sources/*.swift`、外部依存なし・Foundation のみ）。

- `Sources/ElmParse.swift` — Elm ソースの行指向スキャナ（module / import / 行種別 / union constructor）
- `Sources/TreeModel.swift` — 木構造（stick figure）の表現と「本当に木か」の検証
- `Sources/Packing.swift`  — Lang の tree theorem の数値求解（射影＋インフレーション法）
- `Sources/Origami.swift`  — 川崎定理・前川定理・単頂点平坦折り可能性（crimp 簡約）の検証
- `Sources/SVG.swift`      — 図の描画のみ（判定は一切しない）
- `Sources/main.swift`     — ドライバ

## 実行

```sh
swiftc -O Sources/*.swift -o bin/origami
./bin/origami <path-to-elm-web/src> out/
```

出力は `out/report.md` と SVG 3 枚。

## 出力物

| ファイル | 内容 |
|---|---|
| `out/report.md` | 全計算結果（この README の元データ） |
| `out/packing-uniform.svg` | 円配置図（辺長=一様）※展開図ではない |
| `out/packing-loc.svg` | 円配置図（辺長=LOC 重み）※展開図ではない |
| `out/cp-routing.svg` | **展開図**（ルーティング木に対応する square molecule / 4フラップ基本形） |

---

## 比喩の部分と、幾何的に検証した部分の切り分け

**比喩（人間が決めた対応付け。数学的根拠はない）**

- 「ページ／View の末端 = 角（フラップ）」という対応
- 「枝の長さ = そのノードに帰属するコード行数 / 10」という対応
- 共有モジュール（`Data.Articles`）を複製して木に展開する、という選択

**幾何（プログラムが実際に計算・検証した部分）**

- Lang の tree theorem の距離条件 `‖u_i − u_j‖ ≥ m · d_T(i,j)` を全ペアで再評価（min slack を出力）
- スケール `m` の最大化（既知の最適点配置 8 ケースと突き合わせて求解器を検証済み）
- 川崎定理（交互和 = 0）、前川定理（|M−V| = 2）を実座標から計算
- 単頂点の M/V 割り当ての平坦折り可能性を crimp 簡約で判定（degree-4 の教科書解と一致することを自己テスト）

---

## STEP 1 — 構造抽出

| module | file | total | code | comment | blank | string-literal |
|---|---|---:|---:|---:|---:|---:|
| `Api.Endpoint` | `Api/Endpoint.elm` | 11 | 8 | 0 | 3 | 0 |
| `Article.Articles.R8.ElmBlog` | `Article/Articles/R8/ElmBlog.elm` | 29 | 15 | 0 | 7 | 7 |
| `Article.Slug` | `Article/Slug.elm` | 35 | 14 | 3 | 18 | 0 |
| `Data.Articles` | `Data/Articles.elm` | 25 | 19 | 2 | 4 | 0 |
| `Layout` | `Layout.elm` | 57 | 20 | 0 | 7 | 30 |
| `Main` | `main.elm` | 117 | 99 | 0 | 18 | 0 |
| `Page.About` | `Page/About.elm` | 57 | 47 | 0 | 10 | 0 |
| `Page.Home` | `Page/Home.elm` | 37 | 26 | 0 | 11 | 0 |
| `Page.Post` | `Page/Post.elm` | 65 | 47 | 0 | 18 | 0 |
| `Route` | `Route.elm` | 23 | 18 | 0 | 5 | 0 |

内部 import グラフ:

```
Main       -> Layout, Page.About, Page.Home, Page.Post, Route
Page.About -> Route            (※本文中に参照なし = 死んだ import)
Page.Home  -> Data.Articles
Page.Post  -> Data.Articles
その他     -> 内部 import なし
```

副産物として出てきたコード側の指摘:

- `Api/Endpoint.elm` の `import Article.slug` は小文字始まりで、`Article.Slug` に解決されない。
  このファイルは**コンパイルできない**（`request` に本体がなく `url` も未定義）。
- `Main` は `main.elm` にある。Elm は `Main.elm` を要求する。
- `Main` から到達できないモジュール: `Api.Endpoint`, `Article.Slug`, `Article.Articles.R8.ElmBlog`。
- `Page/About.elm:8` の `import Route exposing (Route(..))` は本文で一度も使われていない
  （`Route(..)` を `Route.elm` の constructor 定義まで展開したうえでトークン走査した結果）。

## STEP 2 — 木構造への変換

共有モジュール（in-degree ≥ 2）は `Data.Articles` と `Route` の 2 つ。扱いは以下の通り。

| 共有モジュール | 方針 | 理由 |
|---|---|---|
| `Data.Articles` | **各利用箇所に複製**して木に展開（LOC を 2 分割して `HomeList` と `PostTitle` の枝に加算） | UI 上の同一性を持たない純粋なデータ／クエリ層で、複製しても「角」の意味が壊れないため |
| `Route` | **複製せず spine の分岐節点 `Router` そのものとして扱う** | 分岐構造を定義しているモジュールなので、角ではなく分岐点が対応物。加えて `Page.About` 側の参照は死に import なので、実質 in-degree は 1 |

得られた木（`Root` は `Main.view` + `Layout.view` の合成点）:

```
Root ─┬─ Chrome            (leaf)   Layout の header/nav/styles
      └─ Router ─┬─ HomeHub ── HomeList        (leaf)
                 ├─ PostHub ─┬─ PostTitle      (leaf)
                 │           └─ PostBody       (leaf)
                 ├─ AboutHub ┬─ AboutProfile   (leaf)
                 │           └─ AboutLinks     (leaf)
                 └─ NotFound (leaf)
```

- 木の検証: **OK** — 単一根、12 ノード / 11 辺 / **葉 7**、深さ 3
- 葉の定義: 「View 合成グラフの終端（他の View 関数を呼ばない描画単位）」

| 辺 | 長さ(一様) | 長さ(LOC) | LOC 長の根拠 |
|---|---:|---:|---|
| `Root -> Chrome` | 1.0000 | 2.0000 | Layout.elm code lines / 10 |
| `Root -> Router` | 1.0000 | 9.9000 | main.elm code lines / 10 |
| `Router -> HomeHub` | 1.0000 | 0.5000 | Route.elm / 4 routes / 10 |
| `Router -> PostHub` | 1.0000 | 0.5000 | 同上 |
| `Router -> AboutHub` | 1.0000 | 0.5000 | 同上 |
| `Router -> NotFound` | 1.0000 | 0.5000 | 同上 |
| `HomeHub -> HomeList` | 1.0000 | 3.5500 | Page.Home + Data.Articles/2、/10 |
| `PostHub -> PostTitle` | 1.0000 | 3.3000 | Page.Post/2 + Data.Articles/2、/10 |
| `PostHub -> PostBody` | 1.0000 | 2.3500 | Page.Post/2、/10 |
| `AboutHub -> AboutProfile` | 1.0000 | 2.3500 | Page.About/2、/10 |
| `AboutHub -> AboutLinks` | 1.0000 | 2.3500 | Page.About/2、/10 |

## STEP 3 — 角の実現可能性（Lang の tree theorem）

判定に使った定理: 重み付き木 `T` を持つ uniaxial base が一辺 `s` の正方形から折れる
⇔ 葉を正方形内の点 `u_i` に配置して、全ペアで `‖u_i − u_j‖ ≥ s·m·d_T(i,j)` を満たせる。
このとき Universal Molecule 定理により平坦折り可能な展開図の存在が保証される。
つまり **「折れるか」は最大スケール `m` を求める最適化問題に還元される**。

### 求解器の検証（既知の最適解との突き合わせ）

n 点を単位正方形に置いたときの最小ペア距離の既知最適値 `D(n)`。星型木（全辺 1）では
最適 `m = D(n)/2` になるので、求解器は `D(n)` を再現しなければならない。

| n | D(n) 既知 | D(n) 計算値 | 絶対誤差 |
|---:|---:|---:|---:|
| 2 | 1.414214 (√2) | 1.414214 | 0.000000 |
| 3 | 1.035276 (√6−√2) | 1.035276 | 0.000000 |
| 4 | 1.000000 | 1.000000 | 0.000000 |
| 5 | 0.707107 (√2/2) | 0.707107 | 0.000000 |
| 6 | 0.600925 (√13/6) | 0.600925 | 0.000000 |
| 7 | 0.535898 (4−2√3) | 0.535898 | 0.000000 |
| 8 | 0.517638 ((√6−√2)/2) | 0.517638 | 0.000000 |
| 9 | 0.500000 | 0.500000 | 0.000000 |

8 ケースすべてで既知最適と一致（最大誤差 0.000000）。

### 結果 (1) 全木・辺長一様

- **m = 0.184699**（検証: 全 21 ペア再評価、min slack = 0.000000000、全点が正方形内）
- 拘束が効いている（active な）制約: 10 / 21
- 7 本の角がすべて等長 = **紙の一辺の 0.1847 倍**（15cm 角なら **2.77cm**、24cm 角なら 4.43cm）

葉の座標（単位正方形）:

| leaf | x | y |
|---|---:|---:|
| `AboutLinks` | 0.26120 | 0.00000 |
| `AboutProfile` | 0.00000 | 0.26120 |
| `Chrome` | 0.00000 | 1.00000 |
| `HomeList` | 1.00000 | 0.00000 |
| `NotFound` | 0.50000 | 0.50000 |
| `PostBody` | 1.00000 | 0.73880 |
| `PostTitle` | 0.73880 | 1.00000 |

### 結果 (2) 全木・辺長 LOC 重み

- **m = 0.068102**（min slack = 0.000000000、全点が正方形内）
- active 制約: 5 / 21

| leaf | 木の辺長 | 角の長さ（単位正方形） | 15cm角 | 24cm角 |
|---|---:|---:|---:|---:|
| `HomeList` | 3.5500 | 0.2418 | 3.63 cm | 5.80 cm |
| `PostTitle` | 3.3000 | 0.2247 | 3.37 cm | 5.39 cm |
| `AboutProfile` | 2.3500 | 0.1600 | 2.40 cm | 3.84 cm |
| `AboutLinks` | 2.3500 | 0.1600 | 2.40 cm | 3.84 cm |
| `PostBody` | 2.3500 | 0.1600 | 2.40 cm | 3.84 cm |
| `Chrome` | 2.0000 | 0.1362 | 2.04 cm | 3.27 cm |
| `NotFound` | 0.5000 | 0.0341 | 0.51 cm | 0.82 cm |

（値は `out/report.md` の実行結果に従う。表は実行ごとに末尾桁が動きうる。）

### 参考: 単位正方形が支える等長フラップ本数

星型木（全辺 1）の場合。角の長さ = `m`。

| 本数 n | m | 15cm 角での長さ |
|---:|---:|---:|
| 4 | 0.50000 | 7.50 cm |
| 5 | 0.35355 | 5.30 cm |
| 6 | 0.30046 | 4.51 cm |
| 7 | 0.26795 | 4.02 cm |
| 8 | 0.25882 | 3.88 cm |
| 9 | 0.25000 | 3.75 cm |
| 12 | 0.19436 | 2.92 cm |
| 16 | 0.16667 | 2.50 cm |

**この木（葉 7）が星型なら 0.268 まで伸ばせるのに、実際には 0.185 に留まる**のが
「深さのあるルーティング木」の代償。差の分だけ紙が spine（内部辺 = river）に食われている。

## STEP 4 — 展開図

### 出すもの / 出さないもの

- 葉 7 本の全木については、**展開図を出さない**。最適配置の残余領域が三角形／全辺 active な
  多角形にならず、universal molecule（gusset を含む一般の分子）の生成を実装していないため、
  平坦折り可能性を自分で検証できない。検証していない展開図は出さない、という方針に従う。
  `packing-*.svg` は**円配置図であって展開図ではない**（そう明記して描画している）。
- ルーティング部分木（`Router → Home / Post / About / NotFound`、4 葉の星型）については、
  **展開図を出す**。この場合の最適配置は `m = 1/2`、4 隅に半径 1/2 の円、active 制約は
  正方形の 4 辺。対応する universal molecule は退化して **square molecule**（2 本の対角線＋
  中心から各辺中点への 4 本）になり、内部頂点が中心 1 個だけなので完全に検証できる。

### 自己チェック（プログラムが実際に走らせた検証）

1. **判定器の自己テスト**: 90°×4 の degree-4 頂点で、crimp 簡約が受理する M/V 割り当ては
   16 通り中 **8 通り**（内訳 M=1:4、M=3:4）。教科書解と一致。
2. **square molecule の M/V**: 256 通り中 **112 通り**が平坦折り可能
   （M=3 が 56、M=5 が 56）。**4 回対称な割り当て（対角線 4 本を山、ヒンジ 4 本を谷）は
   前川定理 |M−V|=2 に反するため不可**。これは計算で確認した非自明な帰結。
3. **出力した展開図の検証**（内部頂点は中心 1 個。ヒンジの端点は紙の縁上なので両定理の対象外）:
   - 頂点 (0.500, 0.500)、次数 8、角度 45°×8
   - **川崎定理**: 交互和 = 0.000000000 → **満たす**
   - **前川定理**: M = 3, V = 5, |M−V| = 2 → **満たす**
   - **単頂点 M/V 平坦折り可能性**（crimp 簡約）→ **折れる**
   - 内部頂点が 1 個だけなので、層の重なり順まで含めてこの判定で確定する。

採用した割り当て（右辺ヒンジから反時計回り）:
山 = 右/上/左のヒンジ、谷 = 4 本の対角線と下辺ヒンジ。

出力: `out/cp-routing.svg`（山=実線赤、谷=破線青）。
折ると **4 本の角（長さ = 紙の一辺の 1/2）を持つ uniaxial base** になり、
`Home` / `Post` / `About` / `NotFound` の 4 ルートに 1 対 1 対応する。

## 限界・要追加情報

- **葉の定義が自動化しきれていない。** 「View 合成の終端」というルールは人手で決めた。
  Elm の AST を実際に構文解析すれば（現状は行指向スキャナ）、`case` の分岐単位まで機械的に
  葉を切り出せる。その場合の葉は 7 ではなく 13 前後になり、`m` は下がる。
- **枝長 = LOC/10 は恣意的。** 単調写像であればよい、という以上の根拠はない。
  `Layout.elm` は 57 行中 30 行が CSS 文字列リテラルで、これを数えるか否かで
  `Chrome` の枝長が 2 倍変わる（本レポートは code 行として計上、literal 30 行は除外済み）。
- **`m` は下界であって最適値の証明ではない。** 返す配置は全制約を再評価して検証済みなので
  「その `m` で折れる」ことは確実だが、非凸問題なので大域最適性は主張しない
  （TreeMaker 自身も同じ立場）。既知最適 8 ケースを再現できているのが現状の信頼度の根拠。
- **相互排他ルートを同時に存在する角として扱っている。** `Home` と `About` は同時に描画され
  ないが、木は静的なので全描画状態の和集合を取った。これは人手の判断。
- **全木の展開図が出せていない。** universal molecule（gusset 分子・river 分子）の生成が
  未実装。ここを実装すれば葉 7 本の展開図も検証付きで出せる。
- **`elm.json` がリポジトリに存在しない**ため、外部パッケージの依存関係は解析対象外
  （`Markdown`, `Element`(elm-ui) などは import されているが由来を確認できない）。
