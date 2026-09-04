// main.swift — driver.
// usage: origami <path-to-elm-src> <output-dir>

import Foundation

let args = CommandLine.arguments
let srcRoot = args.count > 1 ? args[1] : "./src"
let outDir  = args.count > 2 ? args[2] : "./out"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

var report = ""
func say(_ s: String = "") { print(s); report += s + "\n" }
func fmt(_ v: Double, _ d: Int = 4) -> String { String(format: "%.\(d)f", v) }

// ---------------------------------------------------------------- step 1: parse
say("# STEP 1 — Elm source extraction")
say()

var files: [String] = []
if let en = FileManager.default.enumerator(atPath: srcRoot) {
    for case let f as String in en where f.hasSuffix(".elm") { files.append(f) }
}
files.sort()

var mods: [String: ElmModule] = [:]
var order: [String] = []
for rel in files {
    let full = (srcRoot as NSString).appendingPathComponent(rel)
    guard let txt = try? String(contentsOfFile: full, encoding: .utf8) else { continue }
    let m = ElmParse.parse(path: rel, text: txt)
    mods[m.name] = m
    order.append(m.name)
}
order.sort()

say("| module | file | total | code | comment | blank | string-literal |")
say("|---|---|---:|---:|---:|---:|---:|")
for n in order {
    let m = mods[n]!
    say("| `\(m.name)` | `\(m.path)` | \(m.totalLines) | \(m.codeLines) | \(m.commentLines) | \(m.blankLines) | \(m.literalLines) |")
}
say()

// filename / module-name consistency (Elm requires them to match)
say("### module-name / filename consistency")
for n in order {
    let m = mods[n]!
    let expected = m.name.replacingOccurrences(of: ".", with: "/") + ".elm"
    let ok = m.path.hasSuffix(expected)
    if !ok { say("- MISMATCH: module `\(m.name)` is in `\(m.path)` (Elm expects `\(expected)`)") }
}
say()

// dependency graph, project-internal edges only
say("### internal import graph")
var deps: [String: [String]] = [:]
var inDegree: [String: Int] = [:]
var unresolved: [(String, String)] = []
for n in order {
    let m = mods[n]!
    for imp in m.imports {
        if mods[imp.module] != nil {
            deps[n, default: []].append(imp.module)
            inDegree[imp.module, default: 0] += 1
        } else if imp.module.contains(".") &&
                  mods.keys.contains(where: { $0.lowercased() == imp.module.lowercased() }) {
            unresolved.append((n, imp.module))
        }
    }
}
for n in order {
    let d = (deps[n] ?? []).sorted()
    say("- `\(n)` -> \(d.isEmpty ? "(no internal imports)" : d.map { "`\($0)`" }.joined(separator: ", "))")
}
say()
if !unresolved.isEmpty {
    say("### imports that do not resolve to any module in this project")
    for (a, b) in unresolved {
        let near = mods.keys.first { $0.lowercased() == b.lowercased() } ?? "?"
        say("- `\(a)` imports `\(b)` — no such module (case-differing candidate: `\(near)`). This file cannot compile.")
    }
    say()
}

// reachability from Main
var reachable = Set<String>()
if mods["Main"] != nil {
    var stack = ["Main"]
    reachable.insert("Main")
    while let x = stack.popLast() {
        for d in deps[x] ?? [] where !reachable.contains(d) { reachable.insert(d); stack.append(d) }
    }
}
let dead = order.filter { !reachable.contains($0) }
say("### reachability from `Main`")
say("- reachable: \(reachable.sorted().map { "`\($0)`" }.joined(separator: ", "))")
say("- NOT reachable (dead for the running app): \(dead.isEmpty ? "none" : dead.map { "`\($0)`" }.joined(separator: ", "))")
say()

// shared modules + unused-import heuristic
say("### shared modules (in-degree >= 2 over internal imports)")
var shared: [String] = []
for n in order where (inDegree[n] ?? 0) >= 2 { shared.append(n) }
if shared.isEmpty { say("- none") }
for n in shared {
    let users = order.filter { (deps[$0] ?? []).contains(n) }
    say("- `\(n)` imported by \(users.map { "`\($0)`" }.joined(separator: ", "))")
}
say()
say("### import-usage heuristic (token scan; `exposing (..)` is undecidable and reported as such)")
for n in order {
    let m = mods[n]!
    for imp in m.imports where mods[imp.module] != nil {
        let u = ElmParse.importLooksUsed(imp, in: m, allModules: mods)
        if u == false {
            say("- `\(n)` line \(imp.line): `import \(imp.module)` — no reference found in the body (likely dead import)")
        } else if u == nil {
            say("- `\(n)` line \(imp.line): `import \(imp.module)` — UNDECIDED by this heuristic")
        }
    }
}
say()

// ---------------------------------------------------------------- step 2: tree
say("# STEP 2 — tree (stick figure) construction")
say()

func loc(_ n: String) -> Double { Double(mods[n]?.codeLines ?? 0) }
func locNoLit(_ n: String) -> Double { Double(mods[n]?.codeLines ?? 0) }

func edgeLen(_ rawLOC: Double) -> Double { max(0.5, rawLOC / 10.0) }

let routeQuarter = loc("Route") / 4.0
let artHalf = loc("Data.Articles") / 2.0

func buildTree(uniform: Bool) -> OrigamiTree {
    func L(_ v: Double, _ why: String) -> (Double, String) { (uniform ? 1.0 : edgeLen(v), uniform ? "uniform 1.0" : why) }
    var e: [TreeEdge] = []
    func add(_ p: String, _ c: String, _ v: Double, _ why: String) {
        let (len, prov) = L(v, why)
        e.append(TreeEdge(parent: p, child: c, length: len, provenance: prov))
    }
    add("Root", "Chrome",       loc("Layout"),                 "Layout.elm code lines / 10")
    add("Root", "Router",       loc("Main"),                   "Main.elm code lines / 10")
    add("Router", "HomeHub",    routeQuarter,                  "Route.elm / 4 route constructors / 10")
    add("Router", "PostHub",    routeQuarter,                  "Route.elm / 4 route constructors / 10")
    add("Router", "AboutHub",   routeQuarter,                  "Route.elm / 4 route constructors / 10")
    add("Router", "NotFound",   routeQuarter,                  "Route.elm / 4 route constructors / 10")
    add("HomeHub", "HomeList",  loc("Page.Home") + artHalf,    "Page.Home + half of Data.Articles / 10")
    add("PostHub", "PostTitle", loc("Page.Post") / 2 + artHalf, "half Page.Post + half Data.Articles / 10")
    add("PostHub", "PostBody",  loc("Page.Post") / 2,          "half Page.Post / 10")
    add("AboutHub", "AboutProfile", loc("Page.About") / 2,     "half Page.About / 10")
    add("AboutHub", "AboutLinks",   loc("Page.About") / 2,     "half Page.About / 10")
    return OrigamiTree(root: "Root", edges: e)
}

let treeUniform = buildTree(uniform: true)
let treeLOC = buildTree(uniform: false)

let v = treeLOC.validateIsTree()
say("- tree check: \(v.ok ? "OK" : "FAILED") — \(v.message)")
say("- depth (root -> deepest leaf, in edges): \(treeLOC.depth)")
say()
say("| edge | length (uniform) | length (LOC) | how the LOC length was derived |")
say("|---|---:|---:|---|")
for (i, e) in treeLOC.edges.enumerated() {
    say("| `\(e.parent)` -> `\(e.child)` | 1.0000 | \(fmt(e.length)) | \(e.provenance) |")
    _ = i
}
say()
say("- leaves (\(treeLOC.leaves.count)): \(treeLOC.leaves.map { "`\($0)`" }.joined(separator: ", "))")
say()

// ---------------------------------------------------------------- step 3: packing
say("# STEP 3 — Lang tree-theorem feasibility")
say()

func dmatrix(_ t: OrigamiTree) -> ([[Double]], [String]) {
    let ls = t.leaves
    var d = [[Double]](repeating: [Double](repeating: 0, count: ls.count), count: ls.count)
    for i in 0..<ls.count {
        for j in 0..<ls.count where i != j { d[i][j] = t.distance(ls[i], ls[j]) }
    }
    return (d, ls)
}

// --- solver validation against known optimal point-spreads in the unit square ---
say("### solver validation (n-leaf star, all edges 1 -> required pairwise distance 2m)")
say("Known optimal minimum pairwise distance D(n) for n points in a unit square;")
say("for this tree the optimum is m = D(n)/2, so the solver must reproduce D(n).")
say()
let knownD: [Int: (Double, String)] = [
    2: ((2.0 as Double).squareRoot(), "sqrt(2)"),
    3: ((6.0 as Double).squareRoot() - (2.0 as Double).squareRoot(), "sqrt(6)-sqrt(2)"),
    4: (1.0, "1"),
    5: ((2.0 as Double).squareRoot() / 2, "sqrt(2)/2"),
    6: ((13.0 as Double).squareRoot() / 6, "sqrt(13)/6"),
    7: (4 - 2 * (3.0 as Double).squareRoot(), "4-2*sqrt(3)"),
    8: (((6.0 as Double).squareRoot() - (2.0 as Double).squareRoot()) / 2, "(sqrt(6)-sqrt(2))/2"),
    9: (0.5, "1/2")
]
say("| n | D(n) known | D(n) found = 2m | abs error |")
say("|---:|---:|---:|---:|")
var worstErr = 0.0
for n in 2...9 {
    var d = [[Double]](repeating: [Double](repeating: 0, count: n), count: n)
    for i in 0..<n { for j in 0..<n where i != j { d[i][j] = 2.0 } }
    let r = Packing.optimise(dmat: d, leafNames: (0..<n).map { "p\($0)" },
                             restarts: 120, iters: 900, seed: UInt64(1234 + n))
    let found = 2 * r.scale
    let err = abs(found - knownD[n]!.0)
    worstErr = max(worstErr, err)
    say("| \(n) | \(fmt(knownD[n]!.0, 6)) (\(knownD[n]!.1)) | \(fmt(found, 6)) | \(fmt(err, 6)) |")
}
say()
say("- worst absolute error over the validation set: \(fmt(worstErr, 6))")
say()

// --- the actual trees ---
struct Solved { var name: String; var tree: OrigamiTree; var res: PackingResult; var radii: [Double] }
var solvedAll: [Solved] = []

func solve(_ label: String, _ t: OrigamiTree, seed: UInt64) -> Solved {
    let (d, names) = dmatrix(t)
    let r = Packing.optimise(dmat: d, leafNames: names, restarts: 900, iters: 700, seed: seed)
    let radii = names.map { r.scale * t.parentEdgeLength($0) }
    return Solved(name: label, tree: t, res: r, radii: radii)
}

for (label, t, sd) in [("full tree, uniform edge lengths", treeUniform, UInt64(11)),
                       ("full tree, LOC-weighted edge lengths", treeLOC, UInt64(22))] {
    let s = solve(label, t, seed: sd)
    solvedAll.append(s)
    say("### \(label)")
    say("- leaves: \(s.res.leafNames.count)")
    say("- best certified scale m = \(fmt(s.res.scale, 6))")
    say("- verification: all pairwise constraints re-evaluated; min slack = \(fmt(s.res.minSlack, 9)), all points inside the square: \(s.res.feasible ? "yes" : "NO")")
    say("- binding (active) constraints: \(s.res.activePairs.count) of \(s.res.leafNames.count * (s.res.leafNames.count - 1) / 2)")
    say()
    say("| leaf | tree edge length | flap length (unit square) | flap length on 15cm | on 24cm |")
    say("|---|---:|---:|---:|---:|")
    for (i, nm) in s.res.leafNames.enumerated() {
        let fl = s.radii[i]
        say("| `\(nm)` | \(fmt(t.parentEdgeLength(nm))) | \(fmt(fl)) | \(fmt(fl * 15, 2)) cm | \(fmt(fl * 24, 2)) cm |")
        _ = i
    }
    say()
    say("| leaf | x | y | (unit square coordinates) |")
    say("|---|---:|---:|---|")
    for (i, nm) in s.res.leafNames.enumerated() {
        say("| `\(nm)` | \(fmt(s.res.points[i].x, 5)) | \(fmt(s.res.points[i].y, 5)) | |")
    }
    say()
    let svg = SVG.packingDiagram(s.res, radii: s.radii,
                                 title: "packing (NOT a crease pattern) — \(label), m=\(fmt(s.res.scale, 4))")
    let fn = label.contains("uniform") ? "packing-uniform.svg" : "packing-loc.svg"
    try? svg.write(toFile: (outDir as NSString).appendingPathComponent(fn), atomically: true, encoding: .utf8)
    say("- packing diagram written to `\(fn)`")
    say()
}

// --- how many flaps fit at a given flap length (uniform star trees) ---
say("### how many equal flaps a unit square supports (uniform star tree, all edges 1)")
say("| flaps n | scale m = flap length | on 15cm square |")
say("|---:|---:|---:|")
for n in 2...16 {
    var d = [[Double]](repeating: [Double](repeating: 0, count: n), count: n)
    for i in 0..<n { for j in 0..<n where i != j { d[i][j] = 2.0 } }
    let r = Packing.optimise(dmat: d, leafNames: (0..<n).map { "p\($0)" },
                             restarts: 90, iters: 900, seed: UInt64(900 + n))
    say("| \(n) | \(fmt(r.scale, 5)) | \(fmt(r.scale * 15, 2)) cm |")
}
say()

// --- the routing-only sub-tree ---
say("### routing sub-tree only (Router -> Home / Post / About / NotFound)")
let star4 = OrigamiTree(root: "Router", edges: [
    TreeEdge(parent: "Router", child: "Home", length: 1, provenance: "one route"),
    TreeEdge(parent: "Router", child: "Post", length: 1, provenance: "one route"),
    TreeEdge(parent: "Router", child: "About", length: 1, provenance: "one route"),
    TreeEdge(parent: "Router", child: "NotFound", length: 1, provenance: "one route")
])
let s4 = solve("routing star", star4, seed: 77)
say("- best certified scale m = \(fmt(s4.res.scale, 6)) (exact optimum is 1/2; four points at the four corners)")
say("- min slack after verification: \(fmt(s4.res.minSlack, 9))")
say("- active constraints: \(s4.res.activePairs.count) (the four sides of the square)")
say()

// ---------------------------------------------------------------- step 4: crease pattern
say("# STEP 4 — crease pattern for the routing sub-tree")
say()

let st = Origami.selfTestDegree4()
say("### self-test of the flat-foldability checker")
say("- degree-4 vertex, four 90-degree sectors: checker accepts \(st.accepted) of 16 M/V assignments (textbook answer: \(st.expected)); breakdown \(st.detail)")
say("- checker \(st.accepted == st.expected ? "AGREES" : "DISAGREES") with the textbook result")
say()

let valid = Origami.squareMoleculeValidAssignments()
say("### square molecule (four corner flaps of length 1/2, all four paper edges active)")
say("- M/V assignments of the 8 creases that pass the crimp test: \(valid.count) of 256")
var byM: [Int: Int] = [:]
for a in valid { byM[a.filter { $0 == 1 }.count, default: 0] += 1 }
say("- grouped by mountain count: " + byM.keys.sorted().map { "M=\($0): \(byM[$0]!)" }.joined(separator: ", "))
say("- a 4-fold symmetric assignment (4 mountains on the diagonals, 4 valleys on the hinges) is \(valid.contains { $0 == [-1, 1, -1, 1, -1, 1, -1, 1] } ? "valid" : "NOT valid — Maekawa forbids |M-V| = 0")")
say()

// Prefer the most readable valid assignment: all four corner bisectors the same, and
// the hinges as uniform as Maekawa allows.  Order is [hingeR, bisNE, hingeT, bisNW,
// hingeL, bisSW, hingeB, bisSE].
let preferred = [1, -1, 1, -1, 1, -1, -1, -1]
if let chosen = (valid.contains(preferred) ? preferred : valid.first) {
    let creases = Origami.squareMolecule(mv: chosen)
    let checks = [Origami.analyseVertex(at: Point(x: 0.5, y: 0.5), creases: creases)].compactMap { $0 }
    say("### verification of the emitted crease pattern")
    say("- interior vertices: \(checks.count) (the four hinge endpoints lie on the paper boundary, where neither theorem applies)")
    for c in checks {
        say("- vertex (\(fmt(c.at.x, 3)), \(fmt(c.at.y, 3))): degree \(c.degree), sectors \(c.sectors.map { fmt($0, 2) }.joined(separator: "/"))")
        say("  - Kawasaki: alternating sum = \(fmt(c.kawasakiAlternatingSum, 9)) -> \(c.kawasakiOK ? "SATISFIED" : "VIOLATED")")
        say("  - Maekawa: M = \(c.mountains), V = \(c.valleys), |M-V| = \(abs(c.mountains - c.valleys)) -> \(c.maekawaOK ? "SATISFIED" : "VIOLATED")")
        say("  - single-vertex M/V flat-foldability (crimp reduction): \(c.mvFoldable ? "FOLDABLE" : "NOT FOLDABLE")")
    }
    let allOK = checks.allSatisfy { $0.kawasakiOK && $0.maekawaOK && $0.mvFoldable }
    say("- overall: \(allOK ? "all interior vertices pass all three checks" : "SOME CHECK FAILED — crease pattern withheld")")
    say()
    say("- assignment used (cyclic from the right-edge hinge): " +
        zip(creases, chosen).map { "\($0.1 == 1 ? "M" : "V"):\($0.0.note)" }.joined(separator: "; "))
    if allOK {
        let svg = SVG.creasePattern(creases, title: "square molecule / 4-flap uniaxial base — routing tree (Home, Post, About, NotFound)")
        try? svg.write(toFile: (outDir as NSString).appendingPathComponent("cp-routing.svg"),
                       atomically: true, encoding: .utf8)
        say("- crease pattern written to `cp-routing.svg`")
    }
    say()
}

try? report.write(toFile: (outDir as NSString).appendingPathComponent("report.md"),
                  atomically: true, encoding: .utf8)
