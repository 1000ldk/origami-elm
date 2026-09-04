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

// Optional design decision: give the paper corners flaps of their own, so that no corner
// region is left with nothing to absorb it.  This changes the tree, and lowers the scale.
var cornerLeaves: [String] = []
if opts.cornerFlaps {
    let shortest = tree.leaves.map { tree.parentEdgeLength($0) }.min() ?? 1.0
    let L = opts.cornerFlapLength ?? shortest
    var e = tree.edges
    for nm in ["corner.SW", "corner.SE", "corner.NE", "corner.NW"] {
        cornerLeaves.append(nm)
        e.append(TreeEdge(parent: tree.root, child: nm, length: L,
                          provenance: "added by --corner-flaps (length \(String(format: "%.4f", L)))"))
    }
    tree = OrigamiTree(root: tree.root, edges: e)
}
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
let leaves = tree.leaves
var dmat = [[Double]](repeating: [Double](repeating: 0, count: leaves.count), count: leaves.count)
for i in 0..<leaves.count {
    for j in 0..<leaves.count where i != j { dmat[i][j] = tree.distance(leaves[i], leaves[j]) }
}
var fixedPts: [Int: Point] = [:]
if opts.cornerFlaps {
    let corners = [Point(x: 0, y: 0), Point(x: 1, y: 0), Point(x: 1, y: 1), Point(x: 0, y: 1)]
    for (k, nm) in cornerLeaves.enumerated() {
        if let i = leaves.firstIndex(of: nm) { fixedPts[i] = corners[k] }
    }
    say("- four flaps pinned to the paper corners (`--corner-flaps`)")
}
let pack = Packing.optimise(dmat: dmat, leafNames: leaves,
                            restarts: opts.restarts, iters: 900, seed: 0x5EED,
                            fixed: fixedPts, compactAfter: opts.compact)
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
var mol = Molecule.build(points: pack.points, activePairs: pack.activePairs, leafNames: leaves)
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

    // Kawasaki depends only on geometry, so check it before searching for an M/V assignment.
    var kawasakiOK = true
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

    var mvOK = false
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

    let complete = (mol.filled == mol.faces) && kawasakiOK && mvOK
    say()
    if complete {
        say("**Verified crease pattern emitted** — every face is filled, and every interior vertex passes Kawasaki, Maekawa and the crimp test.")
        write("crease-pattern.svg", SVG.creasePattern(creases,
              title: "crease pattern — \(leaves.count) flaps, m = \(fmt(pack.scale, 4)) (verified)"))
        say("- `crease-pattern.svg`")
    } else {
        say("**Partial output only.** \(mol.filled) of \(mol.faces) faces are filled" +
            (kawasakiOK ? "" : ", and Kawasaki is violated somewhere") +
            (mvOK ? "" : ", and no verified M/V assignment was found") +
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
