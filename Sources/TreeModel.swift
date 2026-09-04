// TreeModel.swift
// The "stick figure" tree that Lang's tree method takes as input.

import Foundation

struct TreeEdge {
    var parent: String
    var child: String
    var length: Double
    var provenance: String   // how `length` was derived (printed in the report)
}

struct OrigamiTree {
    var root: String
    var edges: [TreeEdge]

    var nodes: [String] {
        var s = Set<String>([root])
        for e in edges { s.insert(e.parent); s.insert(e.child) }
        return s.sorted()
    }

    var childrenOf: [String: [String]] {
        var d: [String: [String]] = [:]
        for e in edges { d[e.parent, default: []].append(e.child) }
        return d
    }

    /// Leaves of the *unrooted* tree: degree-1 nodes.
    var leaves: [String] {
        var deg: [String: Int] = [:]
        for e in edges { deg[e.parent, default: 0] += 1; deg[e.child, default: 0] += 1 }
        return nodes.filter { (deg[$0] ?? 0) <= 1 }
    }

    var depth: Int {
        let ch = childrenOf
        func go(_ n: String) -> Int {
            let cs = ch[n] ?? []
            if cs.isEmpty { return 0 }
            return 1 + (cs.map(go).max() ?? 0)
        }
        return go(root)
    }

    /// Edge length of the edge that ends at `node` (its parent edge).
    func parentEdgeLength(_ node: String) -> Double {
        for e in edges where e.child == node { return e.length }
        return 0
    }

    /// Weighted path length between any two nodes (tree => unique path).
    func distance(_ a: String, _ b: String) -> Double {
        var adj: [String: [(String, Double)]] = [:]
        for e in edges {
            adj[e.parent, default: []].append((e.child, e.length))
            adj[e.child, default: []].append((e.parent, e.length))
        }
        var dist: [String: Double] = [a: 0]
        var stack = [a]
        while let n = stack.popLast() {
            for (m, w) in adj[n] ?? [] where dist[m] == nil {
                dist[m] = dist[n]! + w
                stack.append(m)
            }
        }
        return dist[b] ?? .infinity
    }

    func validateIsTree() -> (ok: Bool, message: String) {
        let n = nodes.count
        let e = edges.count
        if e != n - 1 { return (false, "edge count \(e) != nodes-1 (\(n - 1))") }
        var parentCount: [String: Int] = [:]
        for ed in edges { parentCount[ed.child, default: 0] += 1 }
        for (c, k) in parentCount where k > 1 {
            return (false, "node \(c) has \(k) parents — not a tree")
        }
        // connectivity
        var seen = Set<String>([root])
        var stack = [root]
        let ch = childrenOf
        while let x = stack.popLast() {
            for c in ch[x] ?? [] where !seen.contains(c) { seen.insert(c); stack.append(c) }
        }
        if seen.count != n { return (false, "graph is not connected from root (\(seen.count)/\(n))") }
        return (true, "single-rooted tree: \(n) nodes, \(e) edges, \(leaves.count) leaves")
    }
}
