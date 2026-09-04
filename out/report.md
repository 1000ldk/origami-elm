# STEP 1 — Elm source extraction

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

### module-name / filename consistency
- MISMATCH: module `Main` is in `main.elm` (Elm expects `Main.elm`)

### internal import graph
- `Api.Endpoint` -> (no internal imports)
- `Article.Articles.R8.ElmBlog` -> (no internal imports)
- `Article.Slug` -> (no internal imports)
- `Data.Articles` -> (no internal imports)
- `Layout` -> (no internal imports)
- `Main` -> `Layout`, `Page.About`, `Page.Home`, `Page.Post`, `Route`
- `Page.About` -> `Route`
- `Page.Home` -> `Data.Articles`
- `Page.Post` -> `Data.Articles`
- `Route` -> (no internal imports)

### imports that do not resolve to any module in this project
- `Api.Endpoint` imports `Article.slug` — no such module (case-differing candidate: `Article.Slug`). This file cannot compile.

### reachability from `Main`
- reachable: `Data.Articles`, `Layout`, `Main`, `Page.About`, `Page.Home`, `Page.Post`, `Route`
- NOT reachable (dead for the running app): `Api.Endpoint`, `Article.Articles.R8.ElmBlog`, `Article.Slug`

### shared modules (in-degree >= 2 over internal imports)
- `Data.Articles` imported by `Page.Home`, `Page.Post`
- `Route` imported by `Main`, `Page.About`

### import-usage heuristic (token scan; `exposing (..)` is undecidable and reported as such)
- `Page.About` line 8: `import Route` — no reference found in the body (likely dead import)

# STEP 2 — tree (stick figure) construction

- tree check: OK — single-rooted tree: 12 nodes, 11 edges, 7 leaves
- depth (root -> deepest leaf, in edges): 3

| edge | length (uniform) | length (LOC) | how the LOC length was derived |
|---|---:|---:|---|
| `Root` -> `Chrome` | 1.0000 | 2.0000 | Layout.elm code lines / 10 |
| `Root` -> `Router` | 1.0000 | 9.9000 | Main.elm code lines / 10 |
| `Router` -> `HomeHub` | 1.0000 | 0.5000 | Route.elm / 4 route constructors / 10 |
| `Router` -> `PostHub` | 1.0000 | 0.5000 | Route.elm / 4 route constructors / 10 |
| `Router` -> `AboutHub` | 1.0000 | 0.5000 | Route.elm / 4 route constructors / 10 |
| `Router` -> `NotFound` | 1.0000 | 0.5000 | Route.elm / 4 route constructors / 10 |
| `HomeHub` -> `HomeList` | 1.0000 | 3.5500 | Page.Home + half of Data.Articles / 10 |
| `PostHub` -> `PostTitle` | 1.0000 | 3.3000 | half Page.Post + half Data.Articles / 10 |
| `PostHub` -> `PostBody` | 1.0000 | 2.3500 | half Page.Post / 10 |
| `AboutHub` -> `AboutProfile` | 1.0000 | 2.3500 | half Page.About / 10 |
| `AboutHub` -> `AboutLinks` | 1.0000 | 2.3500 | half Page.About / 10 |

- leaves (7): `AboutLinks`, `AboutProfile`, `Chrome`, `HomeList`, `NotFound`, `PostBody`, `PostTitle`

# STEP 3 — Lang tree-theorem feasibility

### solver validation (n-leaf star, all edges 1 -> required pairwise distance 2m)
Known optimal minimum pairwise distance D(n) for n points in a unit square;
for this tree the optimum is m = D(n)/2, so the solver must reproduce D(n).

| n | D(n) known | D(n) found = 2m | abs error |
|---:|---:|---:|---:|
| 2 | 1.414214 (sqrt(2)) | 1.414214 | 0.000000 |
| 3 | 1.035276 (sqrt(6)-sqrt(2)) | 1.035276 | 0.000000 |
| 4 | 1.000000 (1) | 1.000000 | 0.000000 |
| 5 | 0.707107 (sqrt(2)/2) | 0.707107 | 0.000000 |
| 6 | 0.600925 (sqrt(13)/6) | 0.600925 | 0.000000 |
| 7 | 0.535898 (4-2*sqrt(3)) | 0.535898 | 0.000000 |
| 8 | 0.517638 ((sqrt(6)-sqrt(2))/2) | 0.517638 | 0.000000 |
| 9 | 0.500000 (1/2) | 0.500000 | 0.000000 |

- worst absolute error over the validation set: 0.000000

### full tree, uniform edge lengths
- leaves: 7
- best certified scale m = 0.184699
- verification: all pairwise constraints re-evaluated; min slack = 0.000000000, all points inside the square: yes
- binding (active) constraints: 10 of 21

| leaf | tree edge length | flap length (unit square) | flap length on 15cm | on 24cm |
|---|---:|---:|---:|---:|
| `AboutLinks` | 1.0000 | 0.1847 | 2.77 cm | 4.43 cm |
| `AboutProfile` | 1.0000 | 0.1847 | 2.77 cm | 4.43 cm |
| `Chrome` | 1.0000 | 0.1847 | 2.77 cm | 4.43 cm |
| `HomeList` | 1.0000 | 0.1847 | 2.77 cm | 4.43 cm |
| `NotFound` | 1.0000 | 0.1847 | 2.77 cm | 4.43 cm |
| `PostBody` | 1.0000 | 0.1847 | 2.77 cm | 4.43 cm |
| `PostTitle` | 1.0000 | 0.1847 | 2.77 cm | 4.43 cm |

| leaf | x | y | (unit square coordinates) |
|---|---:|---:|---|
| `AboutLinks` | 1.00000 | 0.73880 | |
| `AboutProfile` | 0.73880 | 1.00000 | |
| `Chrome` | 1.00000 | 0.00000 | |
| `HomeList` | 0.00000 | 1.00000 | |
| `NotFound` | 0.50000 | 0.50000 | |
| `PostBody` | 0.00000 | 0.26120 | |
| `PostTitle` | 0.26120 | 0.00000 | |

- packing diagram written to `packing-uniform.svg`

### full tree, LOC-weighted edge lengths
- leaves: 7
- best certified scale m = 0.068102
- verification: all pairwise constraints re-evaluated; min slack = 0.000000000, all points inside the square: yes
- binding (active) constraints: 5 of 21

| leaf | tree edge length | flap length (unit square) | flap length on 15cm | on 24cm |
|---|---:|---:|---:|---:|
| `AboutLinks` | 2.3500 | 0.1600 | 2.40 cm | 3.84 cm |
| `AboutProfile` | 2.3500 | 0.1600 | 2.40 cm | 3.84 cm |
| `Chrome` | 2.0000 | 0.1362 | 2.04 cm | 3.27 cm |
| `HomeList` | 3.5500 | 0.2418 | 3.63 cm | 5.80 cm |
| `NotFound` | 0.5000 | 0.0341 | 0.51 cm | 0.82 cm |
| `PostBody` | 2.3500 | 0.1600 | 2.40 cm | 3.84 cm |
| `PostTitle` | 3.3000 | 0.2247 | 3.37 cm | 5.39 cm |

| leaf | x | y | (unit square coordinates) |
|---|---:|---:|---|
| `AboutLinks` | 0.09811 | 0.99974 | |
| `AboutProfile` | 0.41141 | 0.93419 | |
| `Chrome` | 0.00000 | 0.00000 | |
| `HomeList` | 0.87668 | 1.00000 | |
| `NotFound` | 0.68639 | 0.52258 | |
| `PostBody` | 1.00000 | 0.09504 | |
| `PostTitle` | 1.00000 | 0.47982 | |

- packing diagram written to `packing-loc.svg`

### how many equal flaps a unit square supports (uniform star tree, all edges 1)
| flaps n | scale m = flap length | on 15cm square |
|---:|---:|---:|
| 2 | 0.70711 | 10.61 cm |
| 3 | 0.51764 | 7.76 cm |
| 4 | 0.50000 | 7.50 cm |
| 5 | 0.35355 | 5.30 cm |
| 6 | 0.30046 | 4.51 cm |
| 7 | 0.26795 | 4.02 cm |
| 8 | 0.25882 | 3.88 cm |
| 9 | 0.25000 | 3.75 cm |
| 10 | 0.21064 | 3.16 cm |
| 11 | 0.19910 | 2.99 cm |
| 12 | 0.19436 | 2.92 cm |
| 13 | 0.18305 | 2.75 cm |
| 14 | 0.17446 | 2.62 cm |
| 15 | 0.17054 | 2.56 cm |
| 16 | 0.16667 | 2.50 cm |

### routing sub-tree only (Router -> Home / Post / About / NotFound)
- best certified scale m = 0.500000 (exact optimum is 1/2; four points at the four corners)
- min slack after verification: 0.000000000
- active constraints: 4 (the four sides of the square)

# STEP 4 — crease pattern for the routing sub-tree

### self-test of the flat-foldability checker
- degree-4 vertex, four 90-degree sectors: checker accepts 8 of 16 M/V assignments (textbook answer: 8); breakdown M=1:4, M=3:4
- checker AGREES with the textbook result

### square molecule (four corner flaps of length 1/2, all four paper edges active)
- M/V assignments of the 8 creases that pass the crimp test: 112 of 256
- grouped by mountain count: M=3: 56, M=5: 56
- a 4-fold symmetric assignment (4 mountains on the diagonals, 4 valleys on the hinges) is NOT valid — Maekawa forbids |M-V| = 0

### verification of the emitted crease pattern
- interior vertices: 1 (the four hinge endpoints lie on the paper boundary, where neither theorem applies)
- vertex (0.500, 0.500): degree 8, sectors 45.00/45.00/45.00/45.00/45.00/45.00/45.00/45.00
  - Kawasaki: alternating sum = 0.000000000 -> SATISFIED
  - Maekawa: M = 3, V = 5, |M-V| = 2 -> SATISFIED
  - single-vertex M/V flat-foldability (crimp reduction): FOLDABLE
- overall: all interior vertices pass all three checks

- assignment used (cyclic from the right-edge hinge): M:hinge -> midpoint of right edge; V:bisector -> corner (1,1); M:hinge -> midpoint of top edge; V:bisector -> corner (0,1); M:hinge -> midpoint of left edge; V:bisector -> corner (0,0); V:hinge -> midpoint of bottom edge; V:bisector -> corner (1,0)
- crease pattern written to `cp-routing.svg`

