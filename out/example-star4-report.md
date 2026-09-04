# 1. source

- source: `/tmp/claude-0/-home-user-origami-elm/ca79bda9-5e49-5675-ac08-ac547113cd39/scratchpad/star4/src`
- 5 Elm modules

| module | file | code | rendering decls |
|---|---|---:|---|
| `A` | `A.elm` | 4 | — |
| `B` | `B.elm` | 4 | — |
| `C` | `C.elm` | 4 | — |
| `D` | `D.elm` | 4 | — |
| `Main` | `Main.elm` | 8 | — |

# 2. tree

- granularity: `module`, shared-module policy: `duplicate`, edge lengths: uniform
- root module: `Main` (auto)
- tree check: **OK** — single-rooted tree: 5 nodes, 4 edges, 4 leaves
- depth: 1

```
Main
├─ A  (1.0000)  [leaf: module]
├─ B  (1.0000)  [leaf: module]
├─ C  (1.0000)  [leaf: module]
└─ D  (1.0000)  [leaf: module]
```

| leaf | kind | edge length | derivation |
|---|---|---:|---|
| `A` | module | 1.0000 | uniform 1.0 |
| `B` | module | 1.0000 | uniform 1.0 |
| `C` | module | 1.0000 | uniform 1.0 |
| `D` | module | 1.0000 | uniform 1.0 |

# 3. packing (Lang's tree theorem)

- leaves (flaps): **4**
- certified scale m = **0.500000**
- verification: every one of the 6 pairwise constraints re-evaluated; min slack = 0.000000000; all points inside the square: yes
- binding (active) constraints: 4

| flap | edge length | flap length (unit square) | on 150mm paper | x | y |
|---|---:|---:|---:|---:|---:|
| `A` | 1.0000 | 0.5000 | 75.0 mm | 0.00000 | 1.00000 |
| `B` | 1.0000 | 0.5000 | 75.0 mm | 0.00000 | 0.00000 |
| `C` | 1.0000 | 0.5000 | 75.0 mm | 1.00000 | 0.00000 |
| `D` | 1.0000 | 0.5000 | 75.0 mm | 1.00000 | 1.00000 |

- circle packing diagram: `packing.svg`

# 4. molecules and crease pattern

- faces of the active-path subdivision: 1
- faces filled with a molecule: 1 / 1  (area coverage 100.0% of the paper)
- crease segments after splitting at interior vertices: 8
- interior vertices to verify: 1
- **Kawasaki** at every interior vertex: SATISFIED (worst |alternating sum| = 0.000000000 degrees)
- **Maekawa** at every interior vertex: SATISFIED
- **single-vertex flat-foldability** (crimp reduction) at every interior vertex: FOLDABLE
- degrees: deg 8: 1

**Verified crease pattern emitted** — every face is filled, and every interior vertex passes Kawasaki, Maekawa and the crimp test.
- `crease-pattern.svg`

Not checked in any case: global layer ordering (deciding flat-foldability of a multi-vertex crease pattern is NP-hard). The guarantee here is Lang's Universal Molecule theorem plus the per-vertex conditions above.

