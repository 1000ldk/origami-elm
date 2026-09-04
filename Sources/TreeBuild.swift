// TreeBuild.swift
// Automatic conversion of a module dependency graph into a single-rooted weighted tree.
// Nothing in here is specific to any particular repository.

import Foundation

enum Granularity: String { case module, view }
enum SharedPolicy: String { case duplicate, hinge }

struct BuildOptions {
    var granularity: Granularity = .view
    var sharedPolicy: SharedPolicy = .duplicate
    var dropUnusedImports = false
    var rootHint: String? = nil
    var nodeCap = 400
    var uniformLengths = false
}

struct BuildResult {
    var tree: OrigamiTree
    var root: String
    var notes: [String]
    var nodeOrigin: [String: String]     // tree node id -> what it came from
    var leafKind: [String: String]       // leaf id -> "module" | "view decl"
    var copies: [String: Int]            // module -> how many times it appears in the tree
    var backEdges: [(String, String)]    // import cycles that had to be broken
    var deadImports: [(String, String)]  // (module, imported) pairs judged unused
}

enum TreeBuild {

    static func internalDeps(_ mods: [String: ElmModule], dropUnused: Bool)
        -> (deps: [String: [String]], dead: [(String, String)]) {
        var deps: [String: [String]] = [:]
        var dead: [(String, String)] = []
        for (n, m) in mods {
            var list: [String] = []
            for imp in m.imports where mods[imp.module] != nil {
                let used = ElmParse.importLooksUsed(imp, in: m, allModules: mods)
                if used == false {
                    dead.append((n, imp.module))
                    if dropUnused { continue }
                }
                if !list.contains(imp.module) { list.append(imp.module) }
            }
            deps[n] = list.sorted()
        }
        return (deps, dead)
    }

    /// Entry module: an explicit hint, else `Main`, else the source that reaches the most
    /// modules, else the module that reaches the most modules.
    static func pickRoot(_ mods: [String: ElmModule], _ deps: [String: [String]],
                         hint: String?) -> String? {
        if let h = hint, mods[h] != nil { return h }
        if mods["Main"] != nil { return "Main" }
        func reach(_ s: String) -> Int {
            var seen = Set([s]); var st = [s]
            while let x = st.popLast() { for d in deps[x] ?? [] where !seen.contains(d) { seen.insert(d); st.append(d) } }
            return seen.count
        }
        var inDeg: [String: Int] = [:]
        for (_, ds) in deps { for d in ds { inDeg[d, default: 0] += 1 } }
        let sources = mods.keys.filter { (inDeg[$0] ?? 0) == 0 }
        let pool = sources.isEmpty ? Array(mods.keys) : sources
        return pool.max { reach($0) < reach($1) }
    }

    static func build(mods: [String: ElmModule], options: BuildOptions) -> BuildResult? {
        var opts = options
        let (deps0, dead) = internalDeps(mods, dropUnused: opts.dropUnusedImports)
        guard let root = pickRoot(mods, deps0, hint: opts.rootHint) else { return nil }

        var notes: [String] = []
        notes.append("root module: `\(root)`" + (opts.rootHint == nil ? " (auto)" : " (given)"))

        // reachable set
        var reachable = Set([root]); var st = [root]
        while let x = st.popLast() {
            for d in deps0[x] ?? [] where !reachable.contains(d) { reachable.insert(d); st.append(d) }
        }
        let deps = deps0.mapValues { $0.filter { reachable.contains($0) } }

        // how many reachable modules import each module
        var parentsOf: [String: [String]] = [:]
        for n in reachable.sorted() { for d in deps[n] ?? [] { parentsOf[d, default: []].append(n) } }

        // BFS depth, used to pick the canonical parent under the hinge policy
        var depth: [String: Int] = [root: 0]
        var bfsParent: [String: String] = [:]
        var queue = [root]; var qi = 0
        while qi < queue.count {
            let x = queue[qi]; qi += 1
            for d in (deps[x] ?? []) where depth[d] == nil {
                depth[d] = depth[x]! + 1; bfsParent[d] = x; queue.append(d)
            }
        }

        // ---- expand the graph into a tree ----
        var edges: [TreeEdge] = []
        var origin: [String: String] = [:]
        var copies: [String: Int] = [:]
        var backEdges: [(String, String)] = []
        var overflow = false

        func freshId(_ module: String) -> String {
            copies[module, default: 0] += 1
            let k = copies[module]!
            return k == 1 ? module : "\(module)~\(k)"
        }

        func expand(_ module: String, parent: String?, ancestors: Set<String>) {
            if overflow { return }
            if origin.count > opts.nodeCap { overflow = true; return }
            let id = freshId(module)
            origin[id] = module
            if let p = parent { edges.append(TreeEdge(parent: p, child: id, length: 1, provenance: "")) }
            for child in deps[module] ?? [] {
                if ancestors.contains(child) { backEdges.append((module, child)); continue }
                let shared = (parentsOf[child]?.count ?? 0) > 1
                if shared && opts.sharedPolicy == .hinge && bfsParent[child] != module { continue }
                expand(child, parent: id, ancestors: ancestors.union([module]))
            }
        }
        expand(root, parent: nil, ancestors: [])

        if overflow {
            // duplication blew up; retry with the hinge policy
            notes.append("shared-module duplication exceeded the node cap (\(opts.nodeCap)); fell back to `hinge`")
            opts.sharedPolicy = .hinge
            edges = []; origin = [:]; copies = [:]; backEdges = []; overflow = false
            expand(root, parent: nil, ancestors: [])
        }

        let rootId = root
        for (m, k) in copies where k > 1 {
            notes.append("shared module `\(m)` (imported by \(parentsOf[m]?.count ?? 0) modules) was duplicated into \(k) tree nodes")
        }
        if opts.sharedPolicy == .hinge {
            for (m, ps) in parentsOf where ps.count > 1 {
                notes.append("shared module `\(m)` kept a single parent `\(bfsParent[m] ?? "?")`; the other \(ps.count - 1) import edge(s) are not represented in the tree")
            }
        }

        // ---- attach view declarations as leaves ----
        var leafKind: [String: String] = [:]
        if opts.granularity == .view {
            var extra: [TreeEdge] = []
            for (id, module) in origin {
                guard let m = mods[module] else { continue }
                for d in m.viewDecls {
                    let lid = "\(id).\(d.name)"
                    origin[lid] = "\(module).\(d.name)"
                    leafKind[lid] = "view decl"
                    extra.append(TreeEdge(parent: id, child: lid, length: 1, provenance: ""))
                }
            }
            edges.append(contentsOf: extra)
        }

        // ---- lengths ----
        func lengthFor(_ id: String) -> (Double, String) {
            if opts.uniformLengths { return (1.0, "uniform 1.0") }
            if leafKind[id] == "view decl" {
                // "Module~k.decl"
                let parts = id.split(separator: ".")
                let declName = String(parts.last!)
                let nodeId = id.dropLast(declName.count + 1)
                let module = origin[String(nodeId)] ?? ""
                let k = max(1, copies[module] ?? 1)
                let loc = mods[module]?.viewDecls.first { $0.name == declName }?.codeLines ?? 0
                let v = Double(loc) / Double(k)
                return (max(0.5, v / 10), "\(loc) code lines of `\(module).\(declName)`" + (k > 1 ? " / \(k) copies" : "") + " / 10")
            }
            let module = origin[id] ?? ""
            let k = max(1, copies[module] ?? 1)
            let loc = opts.granularity == .view ? (mods[module]?.nonViewLOC ?? 0) : (mods[module]?.codeLines ?? 0)
            let label = opts.granularity == .view ? "non-rendering code lines" : "code lines"
            let v = Double(loc) / Double(k)
            return (max(0.5, v / 10), "\(loc) \(label) of `\(module)`" + (k > 1 ? " / \(k) copies" : "") + " / 10")
        }

        edges = edges.map { e in
            let (l, p) = lengthFor(e.child)
            return TreeEdge(parent: e.parent, child: e.child, length: l, provenance: p)
        }

        var tree = OrigamiTree(root: rootId, edges: edges)

        // If the root has a single child it is itself a flap, which is not what we mean by
        // an entry point.  Re-root at the child and fold the edge length into it.
        while (tree.childrenOf[tree.root]?.count ?? 0) == 1, tree.edges.count > 1 {
            let child = tree.childrenOf[tree.root]![0]
            let dropped = tree.parentEdgeLength(child)
            notes.append("root `\(tree.root)` had a single child; re-rooted at `\(child)` (its \(String(format: "%.4f", dropped)) of edge length is absorbed into the root)")
            let newEdges = tree.edges.filter { !($0.parent == tree.root && $0.child == child) }
            tree = OrigamiTree(root: child, edges: newEdges)
        }

        for id in tree.leaves where leafKind[id] == nil { leafKind[id] = "module" }

        return BuildResult(tree: tree, root: tree.root, notes: notes, nodeOrigin: origin,
                           leafKind: leafKind, copies: copies, backEdges: backEdges,
                           deadImports: dead)
    }

    /// ASCII rendering of the tree, for the report.
    static func render(_ t: OrigamiTree, leafKind: [String: String]) -> String {
        var out = ""
        let ch = t.childrenOf
        func go(_ n: String, _ prefix: String, _ isLast: Bool, _ isRoot: Bool) {
            let branch = isRoot ? "" : (isLast ? "└─ " : "├─ ")
            let kind = (ch[n] ?? []).isEmpty ? "  [leaf: \(leafKind[n] ?? "?")]" : ""
            let len = isRoot ? "" : String(format: "  (%.4f)", t.parentEdgeLength(n))
            out += prefix + branch + n + len + kind + "\n"
            let cs = (ch[n] ?? []).sorted()
            for (i, c) in cs.enumerated() {
                go(c, prefix + (isRoot ? "" : (isLast ? "   " : "│  ")), i == cs.count - 1, false)
            }
        }
        go(t.root, "", true, true)
        return out
    }
}
