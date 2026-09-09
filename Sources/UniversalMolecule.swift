// UniversalMolecule.swift
// Lang's universal molecule for a convex axial polygon, computed by insetting.
//
// THE CONSTRUCTION
//
// An *axial polygon* is a face of the active-path subdivision all of whose sides are
// active paths: side (i, i+1) has length exactly m * d_T(node_i, node_j), and every
// diagonal satisfies |p_i - p_j| >= m * d_T(i, j).  Such a polygon is the base of one
// "cone" of the uniaxial base, and the molecule is the crease pattern that fills it.
//
// Inset the polygon by t: every side moves inward by t, so vertex i slides along the
// angle bisector b_i, chosen so that b_i . n_(i-1) = b_i . n_i = 1 with n the inward
// unit normals.  Write c_i = b_i . e_i, with e_i the unit direction of side i; then
// |b_i| = 1 / sin(alpha_i / 2) and c_i = cot(alpha_i / 2).
//
// A point q on the ridge from p_i at inset t is at elevation t in the folded base, and
// |p_i - q| = t / sin(alpha_i / 2).  In the folded base that same distance is the
// hypotenuse of (horizontal m*delta, vertical t), so
//
//        m * delta_i(t) = t * cot(alpha_i / 2) = t * c_i
//
// which says: **vertex i consumes tree length at rate c_i / m per unit inset.**  Hence
// every required distance decays linearly,
//
//        R_ij(t) = R_ij(0) - t * (c_i + c_j),
//
// and because the offset of a side shrinks at exactly the rate c_i + c_(i+1), the
// identity |p_i(t) - p_j(t)| == R_ij(t) is preserved for adjacent pairs.  That identity
// is the algorithm's invariant, and it is re-checked at the top of every recursion: if
// it ever fails, the reduction has run past a branch node, and the face is reported
// rather than filled with something that does not fold.
//
// EVENTS
//   contraction: a side reaches zero length -- two adjacent vertices merge, the ridge
//                traces meet, and a hinge crease drops from the meeting point
//                perpendicular to the side's *base* segment.
//   splitting:   a non-adjacent pair reaches |p_i - p_j| == R_ij -- a gusset appears.
//                The polygon is cut in two along it and each half is reduced on its own.
//   degenerate:  the reduced polygon flattens onto a line.  Nothing is left but the
//                active path itself, which is the river crease, and the face is done.
//
// RIVERS
//
// A river is a tree edge between two branch nodes, and it is what makes the two halves of
// a gusset disagree.  Each half only knows the branch nodes of its own vertices, so when a
// river runs along the gusset, each half drops a hinge where *it* branches, the other half
// has nothing there, and the gusset ends up with a crease that has no partner -- an
// odd-degree vertex, which no flat folding admits.
//
// The cure is to carry the river across: a branch node on the gusset is inserted into the
// other half as a *collinear vertex*.  Its interior angle is straight, so c = cot(90 deg)
// = 0 and it consumes no tree length -- exactly right for a river node, which is a fixed
// point of the tree, not a shrinking flap -- and it insets straight inwards along the
// perpendicular, tracing the level line of that node.  That level line is the partner
// crease.  Which nodes are needed is seeded from the tree and then closed up by iterating
// until both sides land their creases on the gusset at the same points.
//
// The same node also has to be honoured where it is consumed: when a flap runs out exactly
// at a river node, the node's level line turns at the ridge and carries on into the
// neighbouring region, perpendicular to that region's axial base.  Without that arm the
// merge point comes out with odd degree.
//
// Specialising the loop: a triangle collapses to its incentre in one event -- the rabbit
// ear -- and a square to its centre -- the preliminary-base molecule.  A rectangle whose
// short sides are two branch nodes flattens onto a segment -- the classical gusset (river)
// molecule.  All are recovered exactly, so this file subsumes the tangential-polygon
// molecule it replaces.

import Foundation

enum UM {

    // MARK: - small vector helpers

    static func sub(_ a: Point, _ b: Point) -> Point { Point(x: a.x - b.x, y: a.y - b.y) }
    static func add(_ a: Point, _ b: Point) -> Point { Point(x: a.x + b.x, y: a.y + b.y) }
    static func mul(_ a: Point, _ s: Double) -> Point { Point(x: a.x * s, y: a.y * s) }
    static func dot(_ a: Point, _ b: Point) -> Double { a.x * b.x + a.y * b.y }
    static func crs(_ a: Point, _ b: Point) -> Double { a.x * b.y - a.y * b.x }
    static func len(_ a: Point) -> Double { (a.x * a.x + a.y * a.y).squareRoot() }
    static func fmt(_ v: Double) -> String { String(format: "%.6f", v) }

    /// Foot of the perpendicular from `z` onto the line through `a` and `b`.
    static func foot(_ z: Point, _ a: Point, _ b: Point) -> Point {
        let d = sub(b, a)
        let dd = dot(d, d)
        if dd < 1e-18 { return a }
        return add(a, mul(d, dot(sub(z, a), d) / dd))
    }

    /// Offset direction b_i (unit rate against both adjacent sides) and the consumption
    /// rate c_i = b_i . e_i = cot(alpha_i / 2) for every vertex of a CCW polygon.
    static func bisectors(_ p: [Point]) -> (b: [Point], c: [Double])? {
        let n = p.count
        guard n >= 3 else { return nil }
        var nrm: [Point] = []
        var dir: [Point] = []
        for i in 0..<n {
            let d = sub(p[(i + 1) % n], p[i])
            let l = len(d)
            if l < 1e-12 { return nil }
            nrm.append(Point(x: -d.y / l, y: d.x / l))
            dir.append(mul(d, 1 / l))
        }
        var bs: [Point] = []
        var cs: [Double] = []
        for i in 0..<n {
            let a = nrm[(i - 1 + n) % n], b = nrm[i]
            let det = a.x * b.y - a.y * b.x
            // parallel sides: the vertex is straight through, so it travels along the
            // common normal and consumes nothing (cot(90 deg) = 0)
            let bi = abs(det) < 1e-12 ? a
                                      : Point(x: (b.y - a.y) / det, y: (a.x - b.x) / det)
            bs.append(bi)
            cs.append(dot(bi, dir[i]))
        }
        return (bs, cs)
    }

    /// Convex, allowing collinear vertices (a leaf sitting inside an active path) but
    /// rejecting reflex ones, for which the inset is not defined.
    static func isConvex(_ p: [Point]) -> Bool {
        let n = p.count
        guard n >= 3 else { return false }
        for i in 0..<n {
            let a = p[(i - 1 + n) % n], b = p[i], c = p[(i + 1) % n]
            if crs(sub(b, a), sub(c, b)) < -1e-12 { return false }
        }
        return true
    }

    /// Smallest t > 0 with |u + t w| == K - c t, or nil.
    static func splitTime(u: Point, w: Point, K: Double, c: Double) -> Double? {
        let qa = dot(w, w) - c * c
        let qb = 2 * (dot(u, w) + K * c)
        let qc = dot(u, u) - K * K
        var roots: [Double] = []
        if abs(qa) < 1e-14 {
            if abs(qb) > 1e-14 { roots = [-qc / qb] }
        } else {
            let disc = qb * qb - 4 * qa * qc
            if disc >= 0 {
                let s = disc.squareRoot()
                roots = [(-qb - s) / (2 * qa), (-qb + s) / (2 * qa)]
            }
        }
        var best: Double? = nil
        for t in roots where t > 1e-7 && K - c * t >= -1e-9 {
            best = (best == nil) ? t : Swift.min(best!, t)
        }
        return best
    }

    // MARK: - the inset recursion

    /// Signed area of a polygon.  Zero, to numerical tolerance, means the reduced polygon
    /// has flattened onto a line: there is no paper left in it, only the active path.
    static func area(_ p: [Point]) -> Double {
        var a = 0.0
        for i in 0..<p.count {
            let q = p[i], r = p[(i + 1) % p.count]
            a += q.x * r.y - r.x * q.y
        }
        return a / 2
    }

    /// A reduced polygon with no area left is a bare active path: the remaining tree path,
    /// laid out along a segment.  That segment is a crease -- the river -- and the face is
    /// finished.  This is the terminal case of the gusset (river) molecule: a rectangle
    /// whose two short sides are the flaps of two branch nodes reduces to exactly this,
    /// and the segment is the river between them.
    static func emitSegment(_ pts: [Point], into creases: inout [Crease]) {
        var best = (0, 1)
        var bestLen = -1.0
        for i in 0..<pts.count {
            for j in (i + 1)..<pts.count {
                let d = len(sub(pts[i], pts[j]))
                if d > bestLen { bestLen = d; best = (i, j) }
            }
        }
        if bestLen > 1e-9 {
            creases.append(Crease(a: pts[best.0], b: pts[best.1], fold: .mountain, note: "river"))
        }
    }

    /// `R[k][l]` is the required paper distance between polygon positions k and l.
    /// `base[i]` is the segment side i was born on, so a hinge always drops to the
    /// original axial edge rather than to the current inset line.
    static func inset(pts: [Point], base: [(Point, Point)], R: [[Double]],
                      depth: Int, into creases: inout [Crease]) -> (ok: Bool, reason: String) {
        let n = pts.count
        if n < 2 { return (true, "") }
        if n == 2 || abs(area(pts)) < 1e-12 {
            emitSegment(pts, into: &creases)
            return (true, "")
        }
        if depth > 64 { return (false, "the inset did not terminate within 64 events") }
        guard isConvex(pts) else {
            return (false, "the reduced polygon is reflex; the universal molecule is defined for convex axial polygons")
        }
        guard let (bs, cs) = bisectors(pts) else {
            return (false, "the reduced polygon has a degenerate side")
        }

        // Invariant: every side of the reduced polygon is still exactly its reduced tree
        // path.  With rivers carried along (see the splitting event below) this holds by
        // construction; a failure means the reduction ran past a branch node, and the face
        // is reported rather than filled with something that does not fold.
        for i in 0..<n {
            let j = (i + 1) % n
            let g = len(sub(pts[i], pts[j]))
            if abs(g - R[i][j]) > 1e-7 {
                return (false, "reduced side \(i)-\(j) measures \(fmt(g)) but its reduced tree path is \(fmt(R[i][j])); the contraction ran past a branch node, so this face cannot be reduced")
            }
        }

        var tBest = Double.infinity
        var kind = ""
        var ev = (0, 0)
        for i in 0..<n {
            let j = (i + 1) % n
            let rate = cs[i] + cs[j]
            if rate > 1e-9 {
                let t = R[i][j] / rate
                if t < tBest - 1e-12 { tBest = t; kind = "contract"; ev = (i, j) }
            }
        }

        /// A pair whose in-between vertices already lie on the segment does not cut the
        /// polygon in two: one "half" contains no paper.  Such a pair is permanently tight
        /// -- it is a straight run of active path, which is what a river carried onto a
        /// gusset looks like -- and is not a splitting event.
        func halvesHaveArea(_ i: Int, _ j: Int, _ t: Double) -> Bool {
            var q: [Point] = []
            for k in 0..<n { q.append(add(pts[k], mul(bs[k], t))) }
            var loops: [[Int]] = []
            var left: [Int] = []
            for k in i...j { left.append(k) }
            var right: [Int] = []
            for k in j..<n { right.append(k) }
            for k in 0...i { right.append(k) }
            loops.append(left)
            loops.append(right)
            for idx in loops {
                var a = 0.0
                for x in 0..<idx.count {
                    let p1 = q[idx[x]], p2 = q[idx[(x + 1) % idx.count]]
                    a += p1.x * p2.y - p2.x * p1.y
                }
                if abs(a / 2) < 1e-12 { return false }
            }
            return true
        }

        for i in 0..<n {
            for j in (i + 1)..<n where (j - i) % n != 1 && (i - j + n) % n != 1 {
                if let t = splitTime(u: sub(pts[i], pts[j]), w: sub(bs[i], bs[j]),
                                     K: R[i][j], c: cs[i] + cs[j]),
                   t < tBest - 1e-9, halvesHaveArea(i, j, t) {
                    tBest = t; kind = "split"; ev = (i, j)
                }
            }
        }

        if kind.isEmpty || !tBest.isFinite || tBest < -1e-9 {
            return (false, "the inset has no next event; the face cannot be reduced")
        }
        var moved: [Point] = []
        for i in 0..<n { moved.append(add(pts[i], mul(bs[i], tBest))) }
        for i in 0..<n where len(sub(pts[i], moved[i])) > 1e-12 {
            creases.append(Crease(a: pts[i], b: moved[i], fold: .mountain, note: "ridge"))
        }
        var rr = R
        for a in 0..<n {
            for b in 0..<n where a != b { rr[a][b] -= tBest * (cs[a] + cs[b]) }
        }

        if kind == "split" {
            // A gusset: the path between two non-adjacent vertices has become tight, so it
            // is now an active path and cuts the polygon in two.  Each half is again an
            // axial polygon, at elevation tBest rather than 0.
            //
            // THE RIVER.  The two halves are only independent when they agree about where
            // their creases meet the gusset they share.  They do when the tree branches at
            // the same point from both sides -- a star tree, where every median is the one
            // branch node.  They do not when a river runs along the gusset: then each half
            // branches at a node the other does not have, drops its hinge there, and the
            // gusset picks up a crease with no partner on the other side (an odd-degree
            // vertex, which no flat folding admits).
            //
            // The fix is to carry the river along: a branch node on the gusset becomes a
            // *collinear vertex* of the other half's polygon.  Its angle is straight, so it
            // consumes no tree length (c = cot(90 deg) = 0) -- correct, because a river node
            // is a fixed point of the tree -- and it insets straight into the half along the
            // perpendicular, which is exactly the level line of that node.  That is the
            // partner crease the gusset was missing.
            //
            // Which nodes are needed is seeded from the tree (the attach point of every
            // vertex of the other half) and then closed up by iteration: build both halves,
            // look at where each one actually lands creases on the gusset, and give the
            // other half a vertex there, until the two sides agree.
            let (i, j) = ev
            let gusset = (moved[i], moved[j])
            let L = rr[i][j]
            let u = mul(sub(moved[j], moved[i]), 1 / L)

            // where the tree path from vertex k joins the gusset, measured from moved[i]
            func attach(_ k: Int) -> Double { (rr[i][j] + rr[i][k] - rr[j][k]) / 2 }

            var leftIdx: [Int] = []
            for k in i...j { leftIdx.append(k) }
            var rightIdx: [Int] = []
            for k in j..<n { rightIdx.append(k) }
            for k in 0...i { rightIdx.append(k) }

            /// One half: its own vertices, then the river nodes placed on the gusset.
            /// `forward` is true for the half whose vertices run i -> j, so that its gusset
            /// nodes come back in decreasing distance from i and the polygon stays CCW.
            func build(_ idx: [Int], _ nodes: [Double], _ forward: Bool)
                -> (pts: [Point], R: [[Double]], base: [(Point, Point)]) {
                var p: [Point] = idx.map { moved[$0] }
                let order = forward ? nodes.sorted(by: >) : nodes.sorted()
                for a in order { p.append(add(moved[i], mul(u, a))) }
                let m = idx.count
                let tot = p.count
                var r = [[Double]](repeating: [Double](repeating: 0, count: tot), count: tot)
                for x in 0..<tot {
                    for y in 0..<tot where x != y {
                        if x < m && y < m {
                            r[x][y] = rr[idx[x]][idx[y]]
                        } else if x >= m && y >= m {
                            r[x][y] = abs(order[x - m] - order[y - m])
                        } else {
                            let vi = x < m ? idx[x] : idx[y]
                            let a = x < m ? order[y - m] : order[x - m]
                            if vi == i {
                                r[x][y] = a
                            } else if vi == j {
                                r[x][y] = L - a
                            } else {
                                // node -> vertex: along the gusset to where vertex vi joins
                                // it, then out to vi's own tip
                                let ak = attach(vi)
                                r[x][y] = abs(a - ak) + (rr[i][vi] - ak)
                            }
                        }
                    }
                }
                var bs2: [(Point, Point)] = []
                if forward {
                    for k in i..<j { bs2.append(base[k]) }
                } else {
                    for k in j..<n { bs2.append(base[k]) }
                    for k in 0..<i { bs2.append(base[k]) }
                }
                for _ in 0...order.count { bs2.append(gusset) }
                return (p, r, bs2)
            }

            /// Where a half's creases meet the gusset, as distances from moved[i].
            func landings(_ list: [Crease]) -> [Double] {
                var out: [Double] = []
                for c in list {
                    for q in [c.a, c.b] {
                        let d = dot(sub(q, moved[i]), u)
                        if d < 1e-7 || d > L - 1e-7 { continue }
                        if len(sub(q, add(moved[i], mul(u, d)))) > 1e-9 { continue }
                        if !out.contains(where: { abs($0 - d) < 1e-7 }) { out.append(d) }
                    }
                }
                return out
            }

            /// Branch nodes the other half has and this one does not.
            func seed(_ other: [Int], _ mine: [Int]) -> [Double] {
                let own = mine.map { attach($0) }
                var vals: [Double] = []
                for k in other {
                    let a = attach(k)
                    if a < 1e-7 || a > L - 1e-7 { continue }
                    if own.contains(where: { abs($0 - a) < 1e-7 }) { continue }
                    if !vals.contains(where: { abs($0 - a) < 1e-7 }) { vals.append(a) }
                }
                return vals
            }

            let leftInner = leftIdx.filter { $0 != i && $0 != j }
            let rightInner = rightIdx.filter { $0 != i && $0 != j }
            var leftNodes = seed(rightInner, leftInner)
            var rightNodes = seed(leftInner, rightInner)

            for _ in 0..<6 {
                var lc: [Crease] = []
                var rc: [Crease] = []
                let lhs = build(leftIdx, leftNodes, true)
                let l = inset(pts: lhs.pts, base: lhs.base, R: lhs.R, depth: depth + 1, into: &lc)
                if !l.ok { return l }
                let rhs = build(rightIdx, rightNodes, false)
                let r2 = inset(pts: rhs.pts, base: rhs.base, R: rhs.R, depth: depth + 1, into: &rc)
                if !r2.ok { return r2 }
                let la = landings(lc)
                let ra = landings(rc)
                let addL = ra.filter { a in !la.contains(where: { abs($0 - a) < 1e-7 }) }
                let addR = la.filter { a in !ra.contains(where: { abs($0 - a) < 1e-7 }) }
                if addL.isEmpty && addR.isEmpty {
                    creases.append(Crease(a: moved[i], b: moved[j], fold: .valley, note: "gusset"))
                    creases.append(contentsOf: lc)
                    creases.append(contentsOf: rc)
                    return (true, "")
                }
                for a in addL where !leftNodes.contains(where: { abs($0 - a) < 1e-7 }) {
                    leftNodes.append(a)
                }
                for a in addR where !rightNodes.contains(where: { abs($0 - a) < 1e-7 }) {
                    rightNodes.append(a)
                }
            }
            return (false, "the two sides of the gusset did not agree on where their creases meet it, even after carrying every river node across")
        }

        // group maximal runs of vertices that have just become coincident
        var groups: [[Int]] = []
        var used = [Bool](repeating: false, count: n)
        for i in 0..<n where !used[i] {
            var g = [i]
            used[i] = true
            var k = (i + 1) % n
            while k != i && !used[k] && len(sub(moved[k], moved[g[g.count - 1]])) < 1e-9 {
                g.append(k)
                used[k] = true
                k = (k + 1) % n
            }
            groups.append(g)
        }
        // a run that wraps past index 0 comes out as two groups; join them
        if groups.count > 1 {
            let lastGroup = groups[groups.count - 1]
            if len(sub(moved[lastGroup[lastGroup.count - 1]], moved[groups[0][0]])) < 1e-9 {
                groups.removeLast()
                groups[0] = lastGroup + groups[0]
            }
        }

        let heads = groups.map { moved[$0[0]] }
        let collapsed = heads.allSatisfy { len(sub($0, heads[0])) < 1e-9 }
        if collapsed {
            // the whole polygon has come to a point: every side gets its hinge
            let z = heads[0]
            for i in 0..<n {
                creases.append(Crease(a: z, b: foot(z, base[i].0, base[i].1),
                                      fold: .valley, note: "hinge"))
            }
            return (true, "")
        }
        if groups.count == n {
            return (false, "the contraction event at inset \(fmt(tBest)) merged no vertices")
        }

        var keep: [Int] = []
        var nextBase: [(Point, Point)] = []
        for g in groups {
            let z = moved[g[0]]
            // every side strictly inside the group has vanished here
            for k in 0..<(g.count - 1) {
                creases.append(Crease(a: z, b: foot(z, base[g[k]].0, base[g[k]].1),
                                      fold: .valley, note: "hinge"))
            }
            // A group that merged at a river node (a collinear vertex, c = 0) is the moment
            // a flap runs out exactly at that node.  The level line of the node does not
            // stop at the vanished side: it turns at the ridge and carries on into the
            // neighbouring region, perpendicular to that region's axial base.  Without this
            // arm the merge point comes out with odd degree.
            if g.count > 1 && g.contains(where: { abs(cs[$0]) < 1e-9 }) {
                if abs(cs[g[g.count - 1]]) > 1e-9 {
                    creases.append(Crease(a: z, b: foot(z, base[g[g.count - 1]].0, base[g[g.count - 1]].1),
                                          fold: .valley, note: "hinge"))
                }
                if abs(cs[g[0]]) > 1e-9 {
                    let bprev = base[(g[0] - 1 + n) % n]
                    creases.append(Crease(a: z, b: foot(z, bprev.0, bprev.1),
                                          fold: .valley, note: "hinge"))
                }
            }
            keep.append(g[0])
            nextBase.append(base[g[g.count - 1]])
        }

        var nextPts: [Point] = []
        var nextR = [[Double]](repeating: [Double](repeating: 0, count: keep.count),
                               count: keep.count)
        for (a, ka) in keep.enumerated() {
            nextPts.append(moved[ka])
            for (b, kb) in keep.enumerated() where a != b { nextR[a][b] = rr[ka][kb] }
        }
        return inset(pts: nextPts, base: nextBase, R: nextR, depth: depth + 1, into: &creases)
    }

    // MARK: - entry point

    /// Universal molecule of one axial polygon.  `required[i][j]` is m * d_T between the
    /// tree nodes of vertices i and j.  On failure no creases are returned and `reason`
    /// says precisely what the face would need.
    static func molecule(polygon: [Point], required: [[Double]])
        -> (creases: [Crease], ok: Bool, reason: String) {
        let n = polygon.count
        guard n >= 3, required.count == n else { return ([], false, "malformed polygon") }
        var base: [(Point, Point)] = []
        for i in 0..<n { base.append((polygon[i], polygon[(i + 1) % n])) }
        var creases: [Crease] = []
        let r = inset(pts: polygon, base: base, R: required, depth: 0, into: &creases)
        guard r.ok else { return ([], false, r.reason) }
        if let bad = interiorInconsistency(creases, polygon: polygon) {
            return ([], false, bad)
        }
        return (creases, true, "")
    }

    /// Every crease endpoint strictly inside the polygon.  These are the points the
    /// per-vertex theorems have to hold at; a point on the boundary is finished by the
    /// molecule of the neighbouring face.
    static func interiorPoints(_ creases: [Crease], polygon: [Point]) -> [Point] {
        let n = polygon.count
        func strictlyInside(_ q: Point) -> Bool {
            for i in 0..<n {
                if crs(sub(polygon[(i + 1) % n], polygon[i]), sub(q, polygon[i])) <= 1e-9 {
                    return false
                }
            }
            return true
        }
        var pts: [Point] = []
        for c in creases {
            for q in [c.a, c.b] where strictlyInside(q) {
                if !pts.contains(where: { len(sub($0, q)) < 1e-9 }) { pts.append(q) }
            }
        }
        return pts
    }

    /// Does the finished molecule fold?  Every vertex strictly inside the face must have
    /// even degree and a zero alternating sum, or no flat folding exists however the
    /// creases are assigned.  Every molecule this file returns has been through here, so a
    /// filled face is a face whose interior vertices have been checked, not merely one the
    /// recursion happened to finish.
    static func interiorInconsistency(_ creases: [Crease], polygon: [Point]) -> String? {
        let split = Molecule.splitAtPoints(creases)
        let pts = interiorPoints(split, polygon: polygon)
        for v in pts {
            var angles: [Double] = []
            for c in split {
                if len(sub(c.a, v)) < 1e-9 { angles.append(atan2(c.b.y - v.y, c.b.x - v.x)) }
                else if len(sub(c.b, v)) < 1e-9 { angles.append(atan2(c.a.y - v.y, c.a.x - v.x)) }
            }
            if angles.count % 2 == 1 {
                return "the molecule has an interior vertex of odd degree \(angles.count) at (\(fmt(v.x)), \(fmt(v.y))); creases meet there that no flat folding admits"
            }
            angles.sort()
            var alt = 0.0
            for k in 0..<angles.count {
                var d = angles[(k + 1) % angles.count] - angles[k]
                while d <= 0 { d += 2 * Double.pi }
                alt += (k % 2 == 0 ? d : -d)
            }
            if abs(alt) > 1e-6 {
                return "Kawasaki fails inside the molecule at (\(fmt(v.x)), \(fmt(v.y))): alternating sum \(fmt(alt * 180 / Double.pi)) degrees"
            }
        }
        return nil
    }

    /// Add a river node to an axial polygon: a collinear vertex on side (i, i+1), `a` along
    /// it from vertex i, with the tree distances it needs read off the ones already there
    /// (the node lies on the path between vertices i and j, so every distance from it
    /// follows from where the other vertices join that path).
    ///
    /// This is how a branch node that only the neighbouring face knows about is carried into
    /// this one: the node insets straight in, tracing its level line, which is the partner
    /// for the crease the neighbour lands on the path they share.
    static func withNode(polygon: [Point], required: [[Double]], side i: Int, at a: Double)
        -> (polygon: [Point], required: [[Double]])? {
        let n = polygon.count
        guard n >= 3, i >= 0, i < n, required.count == n else { return nil }
        let j = (i + 1) % n
        let L = required[i][j]
        guard a > 1e-7, a < L - 1e-7 else { return nil }
        let e = sub(polygon[j], polygon[i])
        let el = len(e)
        guard el > 1e-12 else { return nil }
        let q = add(polygon[i], mul(e, a / el))

        var row = [Double](repeating: 0, count: n)
        for x in 0..<n {
            if x == i {
                row[x] = a
            } else if x == j {
                row[x] = L - a
            } else {
                let ax = (required[i][j] + required[i][x] - required[j][x]) / 2
                row[x] = abs(a - ax) + (required[i][x] - ax)
            }
        }

        var poly = polygon
        poly.insert(q, at: i + 1)
        let m = n + 1
        var req = [[Double]](repeating: [Double](repeating: 0, count: m), count: m)
        func old(_ x: Int) -> Int { x <= i ? x : x - 1 }
        for x in 0..<m {
            for y in 0..<m where x != y {
                if x == i + 1 {
                    req[x][y] = row[old(y)]
                } else if y == i + 1 {
                    req[x][y] = row[old(x)]
                } else {
                    req[x][y] = required[old(x)][old(y)]
                }
            }
        }
        return (poly, req)
    }

    /// Check that a face really is an axial polygon before trying to fill it.
    /// Returns nil when it is, or the reason it is not.
    static func axialViolation(polygon: [Point], required: [[Double]]) -> String? {
        let n = polygon.count
        for i in 0..<n {
            let j = (i + 1) % n
            let g = len(sub(polygon[i], polygon[j]))
            if abs(g - required[i][j]) > 1e-6 {
                return "side \(i)-\(j) is \(fmt(g)) long but the tree path between its ends is \(fmt(required[i][j])); the side is not an active path"
            }
        }
        for i in 0..<n {
            for j in (i + 1)..<n where (j - i) % n != 1 && (i - j + n) % n != 1 {
                let g = len(sub(polygon[i], polygon[j]))
                if g < required[i][j] - 1e-6 {
                    return "diagonal \(i)-\(j) is \(fmt(g)) but the tree requires at least \(fmt(required[i][j]))"
                }
            }
        }
        return nil
    }
}

// MARK: - self-test

extension UM {

    /// Cases with known answers, so a build can be checked without a repository.
    /// Run with `origami --self-test`.
    static func selfTest() -> [(name: String, ok: Bool, detail: String)] {
        var out: [(name: String, ok: Bool, detail: String)] = []

        func requiredMatrix(_ n: Int, _ f: (Int, Int) -> Double) -> [[Double]] {
            var r = [[Double]](repeating: [Double](repeating: 0, count: n), count: n)
            for i in 0..<n {
                for j in 0..<n where i != j { r[i][j] = f(i, j) }
            }
            return r
        }

        func run(_ name: String, _ poly: [Point], _ req: [[Double]],
                 expectFill: Bool, expectEvents: Int?, expectCentre: Point?) {
            if let bad = axialViolation(polygon: poly, required: req) {
                out.append((name, false, "not an axial polygon to begin with: \(bad)"))
                return
            }
            let m = molecule(polygon: poly, required: req)
            if !expectFill {
                out.append((name, !m.ok, m.ok ? "was filled, but should have been refused"
                                              : "refused as expected — \(m.reason)"))
                return
            }
            guard m.ok else {
                out.append((name, false, "refused: \(m.reason)"))
                return
            }
            var detail = "\(m.creases.count) creases"
            var ok = true
            if let c = expectCentre {
                let hit = m.creases.contains { len(sub($0.a, c)) < 1e-6 || len(sub($0.b, c)) < 1e-6 }
                if !hit { ok = false; detail += "; expected a crease at (\(fmt(c.x)), \(fmt(c.y)))" }
            }
            if let e = expectEvents, m.creases.count != e {
                ok = false
                detail += "; expected \(e) creases"
            }
            // molecule() has already checked the interior vertices; re-state it here so a
            // failure names the case
            if let bad = interiorInconsistency(m.creases, polygon: poly) {
                ok = false
                detail += "; \(bad)"
            }
            // and hold it to the same standard as a finished crease pattern: an M/V
            // assignment that passes Maekawa and the crimp test at every interior vertex
            let split = Molecule.splitAtPoints(m.creases)
            let iv = interiorPoints(split, polygon: poly)
            if iv.isEmpty {
                ok = false
                detail += "; no interior vertices at all"
            } else if Molecule.assignMV(split, vertices: iv) == nil {
                ok = false
                detail += "; no M/V assignment over \(iv.count) interior vertices"
            } else {
                detail += ", \(iv.count) interior vertices, M/V found"
            }
            out.append((name, ok, detail))
        }

        // 1. equilateral triangle: three leaves of length 1 on a common node, m = 1.
        //    Expect the rabbit ear -- 3 ridges to the incentre and 3 hinges.
        let s = 2.0
        let tri = [Point(x: 0, y: 0), Point(x: s, y: 0),
                   Point(x: s / 2, y: s * (3.0).squareRoot() / 2)]
        run("rabbit ear (equilateral triangle)", tri, requiredMatrix(3) { _, _ in 2.0 },
            expectFill: true, expectEvents: 6,
            expectCentre: Point(x: 1.0, y: 1.0 / (3.0).squareRoot()))

        // 2. unit square, four leaves of length 1/2 on a common node.
        //    Expect the preliminary-base molecule: 4 diagonals + 4 hinges to the midpoints.
        let sq = [Point(x: 0, y: 0), Point(x: 1, y: 0), Point(x: 1, y: 1), Point(x: 0, y: 1)]
        run("square molecule (star4)", sq,
            requiredMatrix(4) { i, j in ((i - j) % 4 == 0) ? 0 : (abs(i - j) == 2 ? (2.0).squareRoot() : 1.0) },
            expectFill: true, expectEvents: 8, expectCentre: Point(x: 0.5, y: 0.5))

        // 3. scalene triangle: still one event, still the rabbit ear.
        let sc = [Point(x: 0, y: 0), Point(x: 3, y: 0), Point(x: 0.7, y: 2.2)]
        run("rabbit ear (scalene triangle)", sc,
            requiredMatrix(3) { i, j in len(sub(sc[i], sc[j])) },
            expectFill: true, expectEvents: 6, expectCentre: nil)

        // 4. a quadrilateral spanning a river: A,B on P (1,1), C,D on Q (1,2), P-Q = 1.
        //    A gusset event fires and a river runs along the gusset, so the two halves
        //    branch at different points of it.  Carrying the river nodes across as
        //    collinear vertices is what makes this face fillable; before that it came out
        //    with two odd-degree vertices, one at each end of the river.
        let th = 75.0 * Double.pi / 180
        let qa = Point(x: 0, y: 0)
        let qb = Point(x: 2, y: 0)
        let qc = Point(x: 2 + 3 * cos(th), y: 3 * sin(th))
        let lc = len(qc)
        let xx = (16 - 9 + lc * lc) / (2 * lc)
        let hh = (max(0.0, 16 - xx * xx)).squareRoot()
        let uc = mul(qc, 1 / lc)
        let qd = add(mul(uc, xx), mul(Point(x: -uc.y, y: uc.x), hh))
        let river = [[0.0, 2.0, 3.0, 4.0],
                     [2.0, 0.0, 3.0, 4.0],
                     [3.0, 3.0, 0.0, 3.0],
                     [4.0, 4.0, 3.0, 0.0]]
        run("gusset with a river along it", [qa, qb, qc, qd], river,
            expectFill: true, expectEvents: nil, expectCentre: nil)

        // 5. a quadrilateral with no inscribed circle whose reduction *is* driven by
        //    contraction alone -- two events, a ridge segment between them.  The old
        //    inscribed-circle molecule could not express this at all.  The consistent tree
        //    is read off the polygon's own skeleton: a = t1*c_A and so on.
        let quad = [Point(x: 0, y: 0), Point(x: 2.2, y: 0),
                    Point(x: 3.0, y: 2.4), Point(x: 0.4, y: 2.0)]
        if let (bs1, cs1) = bisectors(quad) {
            var t1 = Double.infinity
            var e1 = (0, 0)
            for i in 0..<4 {
                let j = (i + 1) % 4
                let rate = cs1[i] + cs1[j]
                if rate > 1e-12 {
                    let t = len(sub(quad[i], quad[j])) / rate
                    if t < t1 { t1 = t; e1 = (i, j) }
                }
            }
            var leaf = cs1.map { t1 * $0 }
            var moved: [Point] = []
            for i in 0..<4 { moved.append(add(quad[i], mul(bs1[i], t1))) }
            let keep = (0..<4).filter { $0 != e1.1 }
            let triangle = keep.map { moved[$0] }
            if let (_, cs2) = bisectors(triangle) {
                let t2 = len(sub(triangle[0], triangle[1])) / (cs2[0] + cs2[1])
                let mi = keep.firstIndex(of: e1.0) ?? 0
                let river2 = t2 * cs2[mi]
                for k in 0..<4 where k != e1.0 && k != e1.1 { leaf[k] += t2 * cs1[k] }
                let onP = Set([e1.0, e1.1])
                let req = requiredMatrix(4) { i, j in
                    leaf[i] + leaf[j] + (onP.contains(i) == onP.contains(j) ? 0 : river2)
                }
                run("non-tangential quad, contraction only", quad, req,
                    expectFill: true, expectEvents: nil, expectCentre: nil)
            }
        }

        // 6. the face from 1000ldk/origami-test-elm: four leaves on one node (a star tree,
        //    so no river anywhere), lengths 0.7 / 12.0 / 0.7 / 0.8.  A gusset event fires,
        //    and here the split IS correct -- both halves put their hinge on the gusset at
        //    the single branch node.  It must come out FILLED.
        let mm = ((9 + 4 * 159.04 * 2).squareRoot() - 3) / (2 * 159.04)
        let leafLen = [0.7, 12.0, 0.7, 0.8]     // itemCard, Data, tabButton, view
        let star = [Point(x: 1.5 * mm, y: 0), Point(x: 1, y: 1),
                    Point(x: 0, y: 1.5 * mm), Point(x: 0, y: 0)]
        run("star tree, gusset that works", star,
            requiredMatrix(4) { i, j in mm * (leafLen[i] + leafLen[j]) },
            expectFill: true, expectEvents: nil, expectCentre: nil)

        // 7. the classical gusset (river) molecule: a 2 x (2 + r) rectangle whose four
        //    corners are flaps of length 1, two on P and two on Q, with a river of length r
        //    between them.  Both short sides contract at once, the polygon flattens onto a
        //    segment, and that segment IS the river: 4 ridges + 2 hinges + 1 river crease.
        //    The inset has nothing left to do at that point, which is why the degenerate
        //    polygon is a terminal case rather than a failure.
        for r in [0.5, 1.0, 2.0] {
            let rect = [Point(x: 0, y: 0), Point(x: 2, y: 0),
                        Point(x: 2, y: 2 + r), Point(x: 0, y: 2 + r)]
            let req = requiredMatrix(4) { i, j in
                (i + j == 1 || i + j == 5) ? 2.0 : (2.0 + r)
            }
            run("river rectangle (r = \(fmt(r)))", rect, req,
                expectFill: true, expectEvents: 7, expectCentre: nil)
        }

        return out
    }
}
