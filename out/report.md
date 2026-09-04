# 1. source

- source: `/home/user/1000ldk/elm-web/elm-web/src`
- 10 Elm modules

| module | file | code | rendering decls |
|---|---|---:|---|
| `Api.Endpoint` | `Api/Endpoint.elm` | 8 | — |
| `Article.Articles.R8.ElmBlog` | `Article/Articles/R8/ElmBlog.elm` | 15 | `view`(4) |
| `Article.Slug` | `Article/Slug.elm` | 14 | — |
| `Data.Articles` | `Data/Articles.elm` | 19 | — |
| `Layout` | `Layout.elm` | 20 | `view`(11) `styles`(3) |
| `Main` | `main.elm` | 99 | `view`(13) |
| `Page.About` | `Page/About.elm` | 47 | `me`(19) `viewLink`(3) |
| `Page.Home` | `Page/Home.elm` | 26 | `home`(7) `postItem`(8) |
| `Page.Post` | `Page/Post.elm` | 47 | `view`(13) |
| `Route` | `Route.elm` | 18 | — |

# 2. tree

- granularity: `view`, shared-module policy: `duplicate`, edge lengths: code-size
- root module: `Main` (auto)
- shared module `Route` (imported by 2 modules) was duplicated into 2 tree nodes
- shared module `Data.Articles` (imported by 2 modules) was duplicated into 2 tree nodes
- imports with no reference found in the body: `Page.About` -> `Route` (kept; pass --drop-unused-imports to drop)
- tree check: **OK** — single-rooted tree: 17 nodes, 16 edges, 12 leaves
- depth: 2

```
Main
├─ Layout  (0.6000)
│  ├─ Layout.styles  (0.5000)  [leaf: view decl]
│  └─ Layout.view  (1.1000)  [leaf: view decl]
├─ Main.view  (1.3000)  [leaf: view decl]
├─ Page.About  (2.5000)
│  ├─ Page.About.me  (1.9000)  [leaf: view decl]
│  ├─ Page.About.viewLink  (0.5000)  [leaf: view decl]
│  └─ Route  (0.9000)  [leaf: module]
├─ Page.Home  (1.1000)
│  ├─ Data.Articles  (0.9500)  [leaf: module]
│  ├─ Page.Home.home  (0.7000)  [leaf: view decl]
│  └─ Page.Home.postItem  (0.8000)  [leaf: view decl]
├─ Page.Post  (3.4000)
│  ├─ Data.Articles~2  (0.9500)  [leaf: module]
│  └─ Page.Post.view  (1.3000)  [leaf: view decl]
└─ Route~2  (0.9000)  [leaf: module]
```

| leaf | kind | edge length | derivation |
|---|---|---:|---|
| `Data.Articles` | module | 0.9500 | 19 non-rendering code lines of `Data.Articles` / 2 copies / 10 |
| `Data.Articles~2` | module | 0.9500 | 19 non-rendering code lines of `Data.Articles` / 2 copies / 10 |
| `Layout.styles` | view decl | 0.5000 | 3 code lines of `Layout.styles` / 10 |
| `Layout.view` | view decl | 1.1000 | 11 code lines of `Layout.view` / 10 |
| `Main.view` | view decl | 1.3000 | 13 code lines of `Main.view` / 10 |
| `Page.About.me` | view decl | 1.9000 | 19 code lines of `Page.About.me` / 10 |
| `Page.About.viewLink` | view decl | 0.5000 | 3 code lines of `Page.About.viewLink` / 10 |
| `Page.Home.home` | view decl | 0.7000 | 7 code lines of `Page.Home.home` / 10 |
| `Page.Home.postItem` | view decl | 0.8000 | 8 code lines of `Page.Home.postItem` / 10 |
| `Page.Post.view` | view decl | 1.3000 | 13 code lines of `Page.Post.view` / 10 |
| `Route` | module | 0.9000 | 18 non-rendering code lines of `Route` / 2 copies / 10 |
| `Route~2` | module | 0.9000 | 18 non-rendering code lines of `Route` / 2 copies / 10 |

# 3. packing (Lang's tree theorem)

- leaves (flaps): **12**
- certified scale m = **0.102140**
- verification: every one of the 66 pairwise constraints re-evaluated; min slack = -0.000000000; all points inside the square: yes
- binding (active) constraints: 11

| flap | edge length | flap length (unit square) | on 150mm paper | x | y |
|---|---:|---:|---:|---:|---:|
| `Data.Articles` | 0.9500 | 0.0970 | 14.6 mm | 0.00093 | 0.34218 |
| `Data.Articles~2` | 0.9500 | 0.0970 | 14.6 mm | 0.79233 | 0.10220 |
| `Layout.styles` | 0.5000 | 0.0511 | 7.7 mm | 0.24514 | 0.00000 |
| `Layout.view` | 1.1000 | 0.1124 | 16.9 mm | 1.00000 | 0.68421 |
| `Main.view` | 1.3000 | 0.1328 | 19.9 mm | 0.00000 | 0.00001 |
| `Page.About.me` | 1.9000 | 0.1941 | 29.1 mm | 0.03686 | 1.00000 |
| `Page.About.viewLink` | 0.5000 | 0.0511 | 7.7 mm | 0.35264 | 0.73371 |
| `Page.Home.home` | 0.7000 | 0.0715 | 10.7 mm | 0.15887 | 0.28336 |
| `Page.Home.postItem` | 0.8000 | 0.0817 | 12.3 mm | 0.81039 | 0.99925 |
| `Page.Post.view` | 1.3000 | 0.1328 | 19.9 mm | 0.99905 | 0.00179 |
| `Route` | 0.9000 | 0.0919 | 13.8 mm | 0.28659 | 0.86064 |
| `Route~2` | 0.9000 | 0.0919 | 13.8 mm | 0.73887 | 0.63580 |

- circle packing diagram: `packing.svg`

# 4. molecules and crease pattern

- paper corner (0, 0) is not occupied by a leaf node
- paper corner (1, 0) is not occupied by a leaf node
- paper corner (1, 1) is not occupied by a leaf node
- paper corner (0, 1) is not occupied by a leaf node
- faces of the active-path subdivision: 5
- faces filled with a molecule: 0 / 5  (area coverage 0.0% of the paper)
  - unfilled face ["Data.Articles", "Main.view", "Layout.styles", "Page.Home.home"]: not a tangential polygon (residual 2.97e-02): needs a gusset molecule
  - unfilled face ["Main.view", "Data.Articles", "Page.About.me", "corner15"]: face has a paper corner that is not a leaf node; there is no flap to absorb it
  - unfilled face ["Page.About.me", "Data.Articles", "Page.Home.home", "Page.About.viewLink", "Page.Home.home", "Layout.styles", "Data.Articles~2", "Layout.view", "Page.Home.postItem", "Layout.view", "corner14", "Page.About.me", "Route"]: face has a paper corner that is not a leaf node; there is no flap to absorb it
  - unfilled face ["Data.Articles~2", "Layout.styles", "corner13", "Layout.view", "Data.Articles~2", "Page.Post.view"]: face has a paper corner that is not a leaf node; there is no flap to absorb it
  - unfilled face ["Layout.styles", "Main.view", "corner12"]: face has a paper corner that is not a leaf node; there is no flap to absorb it

**No crease pattern is emitted.** Nothing verifiable was produced, for the reasons above.

