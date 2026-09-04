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
// it ever fails, the face is one whose reduction is not driven by contraction alone and
// needs the general river molecule, which is reported rather than faked.
//
// EVENTS
//   contraction: a side reaches zero length -- two adjacent vertices merge, the ridge
//                traces meet, and a hinge crease drops from the meeting point
//                perpendicular to the side's *base* segment.
//   splitting:   a non-adjacent pair reaches |p_i - p_j| == R_ij -- a gusset (river)
//                appears.  Detected exactly, and reported: splitting the polygon into
//                two independent sub-polygons is NOT correct in general, because the two
//                sub-molecules then drop their hinges onto the new edge at different
//                points (they correspond to different branch nodes of the tree), which
//                produces odd-degree vertices.  See README.
//
// Specialising the loop: a triangle collapses to its incentre in one event -- the rabbit
// ear -- and a square to its centre -- the preliminary-base molecule.  Both are recovered
// exactly, so this file subsumes the tangential-polygon molecule it replaces.

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

    /// `R[k][l]` is the required paper distance between polygon positions k and l.
    /// `base[i]` is the segment side i was born on, so a hinge always drops to the
    /// original axial edge rather than to the current inset line.
    static func inset(pts: [Point], base: [(Point, Point)], R: [[Double]],
                      depth: Int, into creases: inout [Crease]) -> (ok: Bool, reason: String) {
        let n = pts.count
        if n < 3 { return (true, "") }
        if depth > 64 { return (false, "the inset did not terminate within 64 events") }
        guard isConvex(pts) else {
            return (false, "the reduced polygon is reflex; the universal molecule is defined for convex axial polygons")
        }
        guard let (bs, cs) = bisectors(pts) else {
            return (false, "the reduced polygon has a degenerate side")
        }

        // Invariant: every side of the reduced polygon is still exactly its reduced tree
        // path.  Failure means a river/gusset is needed, not that the geometry is wrong.
        for i in 0..<n {
            let j = (i + 1) % n
            let g = len(sub(pts[i], pts[j]))
            if abs(g - R[i][j]) > 1e-7 {
                return (false, "reduced side \(i)-\(j) measures \(fmt(g)) but its reduced tree path is \(fmt(R[i][j])); the contraction is not tree-consistent, so this face needs a river (gusset) molecule, which is not implemented")
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
        for i in 0..<n {
            for j in (i + 1)..<n where (j - i) % n != 1 && (i - j + n) % n != 1 {
                if let t = splitTime(u: sub(pts[i], pts[j]), w: sub(bs[i], bs[j]),
                                     K: R[i][j], c: cs[i] + cs[j]), t < tBest - 1e-9 {
                    tBest = t; kind = "split"; ev = (i, j)
                }
            }
        }

        if kind.isEmpty || !tBest.isFinite || tBest < -1e-9 {
            return (false, "the inset has no next event; the face cannot be reduced")
        }
        if kind == "split" {
            return (false, "a gusset (river) event occurs at inset \(fmt(tBest)), between reduced vertices \(ev.0) and \(ev.1), before any side contracts; the general river molecule is not implemented")
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
        if groups.count < 3 {
            return (false, "the inset collapsed onto a segment rather than a point; this face needs a river (gusset) molecule")
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
        return (r.ok ? creases : [], r.ok, r.reason)
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
