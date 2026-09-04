// main.swift — driver.
//
//   origami <source> [options]
//
// Elm codebase -> module graph -> stick-figure tree -> Lang tree-theorem packing
// -> molecule decomposition -> verified crease pattern (or a precise reason why not).

import Foundation

guard let opts = CLI.parse(CommandLine.arguments) else {
    print(CLI.usage)
    exit(1)
}
if opts.selfTest {
    var failed = 0
    let d4 = Origami.selfTestDegree4()
    let d4ok = d4.accepted == d4.expected
    if !d4ok { failed += 1 }
    print("\(d4ok ? "ok  " : "FAIL") degree-4 crimp test: \(d4.accepted)/\(d4.expected) assignments accepted (\(d4.detail))")
    let sq = Origami.squareMoleculeValidAssignments()
    let sqok = !sq.isEmpty
    if !sqok { failed += 1 }
    print("\(sqok ? "ok  " : "FAIL") square molecule: \(sq.count) flat-foldable M/V assignments")
    for t in UM.selfTest() {
        if !t.ok { failed += 1 }
        print("\(t.ok ? "ok  " : "FAIL") \(t.name): \(t.detail)")
    }
    print(failed == 0 ? "all self-tests passed" : "\(failed) self-test(s) FAILED")
    exit(failed == 0 ? 0 : 1)
}

guard let (srcDir, tempClone) = CLI.resolveSource(opts.source) else {
    FileHandle.standardError.write("cannot resolve source: \(opts.source)\n".data(using: .utf8)!)
    exit(1)
}
defer {
    if let t = tempClone, !opts.keepClone { try? FileManager.default.removeItem(atPath: t) }
}
try? FileManager.default.createDirectory(atPath: opts.outDir, withIntermediateDirectories: true)

var report = ""
func say(_ s: String = "") { if !opts.quiet { print(s) }; report += s + "\n" }
func fmt(_ v: Double, _ d: Int = 4) -> String { String(format: "%.\(d)f", v) }
func write(_ name: String, _ body: String) {
    try? body.write(toFile: (opts.outDir as NSString).appendingPathComponent(name),
                    atomically: true, encoding: .utf8)
}

// ============================================================ 1. parse
say("# 1. source")
say()
say("- source: `\(opts.source)`" + (tempClone != nil ? " (cloned)" : ""))

let files = CLI.findElmFiles(srcDir)
var mods: [String: ElmModule] = [:]
for rel in files {
    let full = (srcDir as NSString).appendingPathComponent(rel)
    guard let txt = try? String(contentsOfFile: full, encoding: .utf8) else { continue }
    let m = ElmParse.parse(path: rel, text: txt)
    mods[m.name] = m
}
guard !mods.isEmpty else {
    FileHandle.standardError.write("no .elm files found under \(srcDir)\n".data(using: .utf8)!)
    exit(1)
}
let order = mods.keys.sorted()
say("- \(mods.count) Elm modules")
say()
say("| module | file | code | rendering decls |")
say("|---|---|---:|---|")
for n in order {
    let m = mods[n]!
    let vs = m.viewDecls.map { "`\($0.name)`(\($0.codeLines))" }.joined(separator: " ")
    say("| `\(m.name)` | `\(m.path)` | \(m.codeLines) | \(vs.isEmpty ? "—" : vs) |")
}
say()

// ============================================================ 2. tree
say("# 2. tree")
say()
var bo = BuildOptions()
bo.granularity = opts.granularity
bo.sharedPolicy = opts.sharedPolicy
bo.dropUnusedImports = opts.dropUnusedImports
bo.rootHint = opts.rootHint
bo.uniformLengths = opts.uniform

guard let built = TreeBuild.build(mods: mods, options: bo) else {
    FileHandle.standardError.write("could not determine a root module\n".data(using: .utf8)!)
    exit(1)
}
var tree = built.tree
let check = tree.validateIsTree()
say("- granularity: `\(opts.granularity.rawValue)`, shared-module policy: `\(opts.sharedPolicy.rawValue)`, edge lengths: \(opts.uniform ? "uniform" : "code-size")")
for n in built.notes { say("- \(n)") }
if !built.deadImports.isEmpty {
    say("- imports with no reference found in the body: " +
        built.deadImports.map { "`\($0.0)` -> `\($0.1)`" }.joined(separator: ", ") +
        (opts.dropUnusedImports ? " (dropped)" : " (kept; pass --drop-unused-imports to drop)"))
}
if !built.backEdges.isEmpty {
    say("- import cycles broken: " + built.backEdges.map { "`\($0.0)` -> `\($0.1)`" }.joined(separator: ", "))
}
say("- tree check: **\(check.ok ? "OK" : "FAILED")** — \(check.message)")
say("- depth: \(tree.depth)")
say()
say("```")
say(TreeBuild.render(tree, leafKind: built.leafKind).trimmingCharacters(in: .newlines))
say("```")
say()
say("| leaf | kind | edge length | derivation |")
say("|---|---|---:|---|")
for l in tree.leaves.sorted() {
    let e = tree.edges.first { $0.child == l }
    say("| `\(l)` | \(built.leafKind[l] ?? "?") | \(fmt(tree.parentEdgeLength(l))) | \(e?.provenance ?? "—") |")
}
say()

guard tree.leaves.count >= 2 else {
    say("Fewer than two leaves; there is no base to design.")
    write("report.md", report)
    exit(0)
}

// ============================================================ 3. packing
say("# 3. packing (Lang's tree theorem)")
say()
func distanceMatrix(_ t: OrigamiTree, _ ls: [String]) -> [[Double]] {
    let mt = TreeMetric(t)
    var d = [[Double]](repeating: [Double](repeating: 0, count: ls.count), count: ls.count)
    for i in 0..<ls.count {
        for j in 0..<ls.count where i != j { d[i][j] = mt.dist(ls[i], ls[j]) }
    }
    return d
}

var leaves = tree.leaves
var dmat = distanceMatrix(tree, leaves)

var pack = Packing.optimise(dmat: dmat, leafNames: leaves,
                            restarts: opts.restarts, iters: 900, seed: 0x5EED,
                            fixed: [:], compactAfter: opts.compact,
                            cornerBias: opts.corners != .none)

// ---------------------------------------------------------------- corners
//
// A paper corner that no leaf occupies is a region of paper with no flap to absorb it, and
// no molecule exists for the face that contains it.  Two ways out, tried in that order:
//
//   1. move a leaf onto the corner.  Free if the packing has the slack for it, and it does
//      not touch the tree, so nothing downstream has to be re-derived.
//   2. give the corner a flap of its own.  That does change the tree, so the length is
//      chosen as the largest one that costs no scale whatsoever:
//
//        L <= |u_j - c| / m - d_T(root, j)   for every existing leaf j and corner c
//        L <= 1 / (2m)                       for two adjacent corner flaps
//
//      If that maximum is <= 0 the corner cannot be given a flap for free, and we say so
//      rather than shrinking the base.  (The previous --corner-flaps used the shortest
//      existing leaf edge, a number with no bearing on feasibility, which made the four
//      corner-to-corner constraints binding and dragged the scale down for every real flap.)
var cornerFixed: [Int: Point] = [:]
if opts.corners == .auto {
    let snap = Packing.snapCorners(points: pack.points, dmat: dmat, keepFraction: opts.cornerKeep)
    if snap.fixed.isEmpty {
        say("- corner snapping: no leaf could be moved onto a paper corner without losing more than \(fmt((1 - opts.cornerKeep) * 100, 1))% of the scale")
    } else {
        let names = snap.fixed.keys.sorted().map { "`\(leaves[$0])`" }.joined(separator: ", ")
        say("- corner snapping: \(names) moved onto paper corners; scale \(fmt(pack.scale, 6)) -> \(fmt(snap.scale, 6))")
    }
    cornerFixed = snap.fixed
    pack = Packing.verify(points: snap.points, dmat: dmat, leafNames: leaves,
                          restartsUsed: opts.restarts)
}

var unoccupied: [Point] = []
if opts.corners != .none {
    for c in Packing.unitCorners where !pack.points.contains(where: { hypot($0.x - c.x, $0.y - c.y) < 1e-9 }) {
        unoccupied.append(c)
    }
}
if !unoccupied.isEmpty {
    let metric0 = TreeMetric(tree)
    var maxL = Double.infinity
    // against every existing leaf: |u_j - c| >= m * (L + d_T(root, j))
    for c in unoccupied {
        for (j, u) in pack.points.enumerated() {
            maxL = min(maxL, hypot(u.x - c.x, u.y - c.y) / pack.scale - metric0.dist(tree.root, leaves[j]))
        }
    }
    // against each other: |c - c'| >= m * 2L, which only bites once there are two of them
    for a in 0..<unoccupied.count {
        for b in (a + 1)..<unoccupied.count {
            let d = hypot(unoccupied[a].x - unoccupied[b].x, unoccupied[a].y - unoccupied[b].y)
            maxL = min(maxL, d / (2 * pack.scale))
        }
    }
    if let cap = opts.cornerFlapLength { maxL = min(maxL, cap) }

    if maxL <= 1e-9 {
        say("- corner flaps: **not added**. The longest flap that would cost no scale is \(fmt(maxL, 6)) <= 0, so every corner flap here would shrink the base. \(unoccupied.count) corner(s) stay unoccupied.")
    } else {
        let cornerName = ["corner.SW", "corner.SE", "corner.NE", "corner.NW"]
        var placed: [String: Point] = [:]
        var edges = tree.edges
        for c in unoccupied {
            let k = Packing.unitCorners.firstIndex { hypot($0.x - c.x, $0.y - c.y) < 1e-9 } ?? 0
            let nm = cornerName[k]
            placed[nm] = c
            edges.append(TreeEdge(parent: tree.root, child: nm, length: maxL,
                                  provenance: String(format: "corner flap, longest that costs no scale (%.4f)", maxL)))
        }
        tree = OrigamiTree(root: tree.root, edges: edges)

        var byName: [String: Point] = [:]
        for (i, nm) in leaves.enumerated() { byName[nm] = pack.points[i] }
        for (nm, c) in placed { byName[nm] = c }
        let oldFixedNames = Set(cornerFixed.keys.map { leaves[$0] })

        leaves = tree.leaves
        dmat = distanceMatrix(tree, leaves)
        var pts: [Point] = []
        var fixed: [Int: Point] = [:]
        for (i, nm) in leaves.enumerated() {
            let q = byName[nm] ?? Point(x: 0.5, y: 0.5)
            pts.append(q)
            if placed[nm] != nil || oldFixedNames.contains(nm) { fixed[i] = q }
        }
        let grown = Packing.polish(points: pts, dmat: dmat, fixed: fixed)
        let after = Packing.verify(points: grown, dmat: dmat, leafNames: leaves,
                                   restartsUsed: opts.restarts)
        say("- corner flaps: \(placed.count) added at the unoccupied corner(s), each of tree-edge length \(fmt(maxL, 6)) — the longest that costs no scale; m \(fmt(pack.scale, 6)) -> \(fmt(after.scale, 6))")
        let recheck = tree.validateIsTree()
        say("- tree check after adding corner flaps: **\(recheck.ok ? "OK" : "FAILED")** — \(recheck.message)")
        pack = after
        cornerFixed = fixed
    }
}

let metric = TreeMetric(tree)
let radii = leaves.map { pack.scale * tree.parentEdgeLength($0) }

say("- leaves (flaps): **\(leaves.count)**")
say("- certified scale m = **\(fmt(pack.scale, 6))**")
say("- verification: every one of the \(leaves.count * (leaves.count - 1) / 2) pairwise constraints re-evaluated; min slack = \(fmt(pack.minSlack, 9)); all points inside the square: \(pack.feasible ? "yes" : "**NO**")")
say("- binding (active) constraints: \(pack.activePairs.count)")
say()
say("| flap | edge length | flap length (unit square) | on \(Int(opts.paperMM))mm paper | x | y |")
say("|---|---:|---:|---:|---:|---:|")
for (i, nm) in leaves.enumerated() {
    say("| `\(nm)` | \(fmt(tree.parentEdgeLength(nm))) | \(fmt(radii[i])) | \(fmt(radii[i] * opts.paperMM, 1)) mm | \(fmt(pack.points[i].x, 5)) | \(fmt(pack.points[i].y, 5)) |")
}
say()
write("packing.svg", SVG.packingDiagram(pack, radii: radii,
      title: "circle packing (NOT a crease pattern) — \(leaves.count) flaps, m = \(fmt(pack.scale, 4))"))
say("- circle packing diagram: `packing.svg`")
say()

// ============================================================ 4. molecules
say("# 4. molecules and crease pattern")
say()
var mol = Molecule.build(points: pack.points, activePairs: pack.activePairs,
                         leafNames: leaves, tree: tree, metric: metric, scale: pack.scale)
for n in mol.notes { say("- \(n)") }
say("- faces of the active-path subdivision: \(mol.faces)")
say("- faces filled with a molecule: \(mol.filled) / \(mol.faces)  (area coverage \(fmt(mol.coverage * 100, 1))% of the paper)")
for u in mol.unfilled {
    say("  - unfilled face \(u.verts.map { $0 < leaves.count ? leaves[$0] : "corner\($0)" }): \(u.reason)")
}

if mol.filled == 0 {
    say()
    say("**No crease pattern is emitted.** Nothing verifiable was produced, for the reasons above.")
} else {
    var creases = Molecule.splitAtPoints(mol.creases)
    let iv = Molecule.interiorVertices(creases)
    say("- crease segments after splitting at interior vertices: \(creases.count)")
    say("- interior vertices to verify: \(iv.count)")

    // The per-vertex theorems only say anything about a *complete* decomposition.  With
    // faces left unfilled, a molecule's hinge foot lands on an axial crease that its
    // missing neighbour never met, the vertex comes out with odd degree, and Kawasaki
    // fails for a reason that has nothing to do with the geometry being wrong.  Reporting
    // that as "Kawasaki VIOLATED" names the wrong culprit, so say what is actually true.
    let complete = mol.filled == mol.faces
    let mismatches = Molecule.hingeMismatches(creases)
    if !mismatches.isEmpty {
        say("- \(mismatches.count) interior point(s) where a hinge crease meets an axial crease with no partner from the other side" +
            (complete ? " — neighbouring molecules disagree about where their hinges meet the path they share"
                      : " — expected, since \(mol.faces - mol.filled) face(s) are unfilled"))
    }

    var kawasakiOK = false
    var mvOK = false

    if !complete {
        say("- **per-vertex conditions not evaluated**: \(mol.filled) of \(mol.faces) faces are filled, so the crease pattern is incomplete. Kawasaki, Maekawa and the crimp test are only meaningful once every face carries a molecule; running them on a partial map would report a violation that is an artefact of the missing faces, not of the geometry.")
    } else {

    // Kawasaki depends only on geometry, so check it before searching for an M/V assignment.
    kawasakiOK = true
    var worstAlt = 0.0
    var oddDegree = 0
    for v in iv {
        guard let c = Origami.analyseVertex(at: v, creases: creases) else { continue }
        worstAlt = max(worstAlt, abs(c.kawasakiAlternatingSum))
        if c.degree % 2 == 1 { oddDegree += 1 }
        if !c.kawasakiOK { kawasakiOK = false }
    }
    if oddDegree > 0 {
        say("- \(oddDegree) interior vertex/vertices have ODD degree, which no flat folding admits. This means neighbouring molecules do not agree on where their hinge creases meet the shared axial path — the decomposition is incomplete, not merely unassigned.")
    }
    say("- **Kawasaki** at every interior vertex: \(kawasakiOK ? "SATISFIED" : "VIOLATED") (worst |alternating sum| = \(fmt(worstAlt, 9)) degrees)")

    if kawasakiOK, let mv = Molecule.assignMV(creases) {
        for i in creases.indices { creases[i].fold = mv[i] }
        var allOK = true
        var checks: [VertexCheck] = []
        for v in iv {
            guard let c = Origami.analyseVertex(at: v, creases: creases) else { continue }
            checks.append(c)
            if !(c.kawasakiOK && c.maekawaOK && c.mvFoldable) { allOK = false }
        }
        mvOK = allOK
        mol.interiorVertices = checks
        say("- **Maekawa** at every interior vertex: \(checks.allSatisfy { $0.maekawaOK } ? "SATISFIED" : "VIOLATED")")
        say("- **single-vertex flat-foldability** (crimp reduction) at every interior vertex: \(checks.allSatisfy { $0.mvFoldable } ? "FOLDABLE" : "NOT FOLDABLE")")
        say("- degrees: " + Dictionary(grouping: checks, by: { $0.degree }).keys.sorted()
            .map { d in "deg \(d): \(checks.filter { $0.degree == d }.count)" }.joined(separator: ", "))
    } else if kawasakiOK {
        say("- **no M/V assignment found** within the search budget; only the crease geometry is emitted")
    }

    }  // end of the complete-decomposition branch

    let verified = complete && kawasakiOK && mvOK
    say()
    if verified {
        say("**Verified crease pattern emitted** — every face is filled, and every interior vertex passes Kawasaki, Maekawa and the crimp test.")
        write("crease-pattern.svg", SVG.creasePattern(creases,
              title: "crease pattern — \(leaves.count) flaps, m = \(fmt(pack.scale, 4)) (verified)"))
        say("- `crease-pattern.svg`")
    } else {
        say("**Partial output only.** \(mol.filled) of \(mol.faces) faces are filled" +
            (!complete ? "" : (kawasakiOK ? "" : ", and Kawasaki is violated somewhere")) +
            (!complete ? "" : (mvOK ? "" : ", and no verified M/V assignment was found")) +
            ". This is a molecule map, not a foldable crease pattern; it is labelled as such in the file.")
        write("molecules-partial.svg", SVG.creasePattern(creases,
              title: "PARTIAL molecule map — NOT a foldable crease pattern (\(mol.filled)/\(mol.faces) faces filled)"))
        say("- `molecules-partial.svg`")
    }
    say()
    say("Not checked in any case: global layer ordering (deciding flat-foldability of a multi-vertex crease pattern is NP-hard). The guarantee here is Lang's Universal Molecule theorem plus the per-vertex conditions above.")
}

say()
write("report.md", report)
if opts.quiet { print("wrote \(opts.outDir)/report.md") }
