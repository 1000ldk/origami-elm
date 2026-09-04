// Molecule.swift
// From a solved packing to an actual crease pattern.
//
// Pipeline:
//   1. active-path graph   -- leaf pairs whose distance constraint is tight
//   2. planar subdivision  -- those segments plus the paper boundary cut the square into faces
//   3. molecules           -- each face that admits an inscribed circle gets the "tangential
//                             polygon" molecule (the triangle case of which is the rabbit ear,
//                             and the square case of which is the preliminary-base molecule)
//   4. assembly            -- molecule creases plus the interior active paths (axial creases)
//   5. M/V assignment      -- backtracking search, every vertex checked with Origami's crimp test
//   6. verification        -- Kawasaki / Maekawa / crimp at EVERY interior vertex
//
// A face that is not tangential needs a gusset (the general universal molecule), which is not
// implemented.  Such faces are left unfilled and reported; the output is then labelled a
// partial molecule map, not a crease pattern.

import Foundation

struct Seg {
    var a: Int
    var b: Int
    var kind: String   // "active" | "paper"
}

struct Face {
    var verts: [Int]        // in CCW order
    var area: Double
    var touchesPaperCorner: Bool
    var allEdgesActive: Bool
}

struct MoleculeReport {
    var faces: Int
    var filled: Int
    var unfilled: [(verts: [Int], reason: String)]
    var coverage: Double        // filled area / paper area
    var creases: [Crease]
    var interiorVertices: [VertexCheck]
    var kawasakiAllOK: Bool
    var mvAssigned: Bool
    var mvAllOK: Bool
    var crossingActivePaths: Bool
    var notes: [String]
}

enum Molecule {

    static let eps = 1e-7

    // MARK: - planar subdivision

    static func subdivide(points: [Point], activePairs: [(Int, Int)]) -> (verts: [Point], segs: [Seg], corners: Set<Int>, notes: [String]) {
        var verts = points
        var notes: [String] = []
        var corners = Set<Int>()
        let paperCorners = [Point(x: 0, y: 0), Point(x: 1, y: 0), Point(x: 1, y: 1), Point(x: 0, y: 1)]
        for c in paperCorners {
            if verts.contains(where: { hypot($0.x - c.x, $0.y - c.y) < 1e-9 }) {
                // a leaf already sits on this corner, so there is a flap to absorb it
            } else {
                verts.append(c)
                corners.insert(verts.count - 1)
                notes.append("paper corner (\(Int(c.x)), \(Int(c.y))) is not occupied by a leaf node")
            }
        }

        var segs: [Seg] = activePairs.map { Seg(a: $0.0, b: $0.1, kind: "active") }

        // paper boundary, split at every vertex that lies on it
        let sides: [(fixed: Int, value: Double)] = [(1, 0.0), (1, 1.0), (0, 0.0), (0, 1.0)]  // y=0, y=1, x=0, x=1
        for s in sides {
            var on: [(Int, Double)] = []
            for (i, p) in verts.enumerated() {
                let coord = s.fixed == 1 ? p.y : p.x
                let along = s.fixed == 1 ? p.x : p.y
                if abs(coord - s.value) < 1e-9 { on.append((i, along)) }
            }
            on.sort { $0.1 < $1.1 }
            for k in 0..<max(0, on.count - 1) {
                segs.append(Seg(a: on[k].0, b: on[k + 1].0, kind: "paper"))
            }
        }

        // de-duplicate
        var seen = Set<String>()
        segs = segs.filter { s in
            let key = "\(min(s.a, s.b))-\(max(s.a, s.b))"
            if seen.contains(key) { return false }
            seen.insert(key); return true
        }
        return (verts, segs, corners, notes)
    }

    /// Do any two segments cross in their interiors?  If so the subdivision is not planar and
    /// the face walk would be meaningless.
    static func hasCrossing(_ verts: [Point], _ segs: [Seg]) -> Bool {
        func cross(_ o: Point, _ a: Point, _ b: Point) -> Double {
            (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
        }
        for i in 0..<segs.count {
            for j in (i + 1)..<segs.count {
                let s = segs[i], t = segs[j]
                if s.a == t.a || s.a == t.b || s.b == t.a || s.b == t.b { continue }
                let p1 = verts[s.a], p2 = verts[s.b], p3 = verts[t.a], p4 = verts[t.b]
                let d1 = cross(p3, p4, p1), d2 = cross(p3, p4, p2)
                let d3 = cross(p1, p2, p3), d4 = cross(p1, p2, p4)
                if ((d1 > eps && d2 < -eps) || (d1 < -eps && d2 > eps)) &&
                   ((d3 > eps && d4 < -eps) || (d3 < -eps && d4 > eps)) { return true }
            }
        }
        return false
    }

    /// Walk the half-edges of the planar subdivision and return the bounded faces.
    static func faces(_ verts: [Point], _ segs: [Seg], corners: Set<Int>) -> [Face] {
        var adj: [Int: [(v: Int, seg: Int)]] = [:]
        for (k, s) in segs.enumerated() {
            adj[s.a, default: []].append((s.b, k))
            adj[s.b, default: []].append((s.a, k))
        }
        for (v, list) in adj {
            adj[v] = list.sorted {
                atan2(verts[$0.v].y - verts[v].y, verts[$0.v].x - verts[v].x) <
                atan2(verts[$1.v].y - verts[v].y, verts[$1.v].x - verts[v].x)
            }
        }
        var visited = Set<String>()
        var out: [Face] = []
        for (k, s) in segs.enumerated() {
            for (from, to) in [(s.a, s.b), (s.b, s.a)] {
                let key = "\(from)>\(to)"
                if visited.contains(key) { continue }
                var loop: [Int] = []
                var cu = from, cv = to
                var guardCount = 0
                while guardCount < 4 * segs.count + 8 {
                    guardCount += 1
                    visited.insert("\(cu)>\(cv)")
                    loop.append(cu)
                    guard let list = adj[cv], let idx = list.firstIndex(where: { $0.v == cu }) else { break }
                    let nxt = list[(idx - 1 + list.count) % list.count]
                    cu = cv; cv = nxt.v
                    if cu == from && cv == to { break }
                }
                var area = 0.0
                for i in 0..<loop.count {
                    let p = verts[loop[i]], q = verts[loop[(i + 1) % loop.count]]
                    area += p.x * q.y - q.x * p.y
                }
                area /= 2
                if area > eps && loop.count >= 3 {
                    let touches = loop.contains { corners.contains($0) }
                    var allActive = true
                    for i in 0..<loop.count {
                        let a = loop[i], b = loop[(i + 1) % loop.count]
                        if !segs.contains(where: { ($0.a == a && $0.b == b) || ($0.a == b && $0.b == a) ? $0.kind == "active" : false }) {
                            allActive = false
                        }
                    }
                    out.append(Face(verts: loop, area: area, touchesPaperCorner: touches, allEdgesActive: allActive))
                }
                _ = k
            }
        }
        return out
    }

    // MARK: - the tangential-polygon molecule

    /// Least-squares solve for a point equidistant from every edge line of a convex polygon.
    /// Returns nil when no such point exists (the polygon needs a gusset instead).
    static func inscribedCentre(_ poly: [Point]) -> (centre: Point, r: Double, residual: Double)? {
        let k = poly.count
        guard k >= 3 else { return nil }
        // rows: n_i . X - r = n_i . P_i   with n_i the inward unit normal of edge i
        var ata = [[Double]](repeating: [Double](repeating: 0, count: 3), count: 3)
        var atb = [Double](repeating: 0, count: 3)
        var rows: [([Double], Double)] = []
        for i in 0..<k {
            let p = poly[i], q = poly[(i + 1) % k]
            let dx = q.x - p.x, dy = q.y - p.y
            let len = hypot(dx, dy)
            if len < 1e-12 { return nil }
            // CCW polygon -> inward normal is the left normal of (p -> q)
            let nx = -dy / len, ny = dx / len
            let row = [nx, ny, -1.0]
            let rhs = nx * p.x + ny * p.y
            rows.append((row, rhs))
            for a in 0..<3 {
                for b in 0..<3 { ata[a][b] += row[a] * row[b] }
                atb[a] += row[a] * rhs
            }
        }
        // 3x3 solve (Gaussian elimination with partial pivoting)
        var m = ata
        var v = atb
        for col in 0..<3 {
            var piv = col
            for r in (col + 1)..<3 where abs(m[r][col]) > abs(m[piv][col]) { piv = r }
            if abs(m[piv][col]) < 1e-14 { return nil }
            m.swapAt(col, piv); v.swapAt(col, piv)
            for r in 0..<3 where r != col {
                let f = m[r][col] / m[col][col]
                for c in col..<3 { m[r][c] -= f * m[col][c] }
                v[r] -= f * v[col]
            }
        }
        let x = v[0] / m[0][0], y = v[1] / m[1][1], r = v[2] / m[2][2]
        var residual = 0.0
        for (row, rhs) in rows {
            residual = max(residual, abs(row[0] * x + row[1] * y + row[2] * r - rhs))
        }
        if r <= 1e-9 { return nil }
        return (Point(x: x, y: y), r, residual)
    }

    /// Creases of the molecule: a ridge crease from the centre to every polygon vertex, and a
    /// hinge crease from the centre perpendicular to every polygon edge.
    static func moleculeCreases(_ poly: [Point], centre: Point) -> [Crease] {
        var out: [Crease] = []
        for p in poly {
            out.append(Crease(a: centre, b: p, fold: .mountain, note: "ridge"))
        }
        let k = poly.count
        for i in 0..<k {
            let p = poly[i], q = poly[(i + 1) % k]
            let dx = q.x - p.x, dy = q.y - p.y
            let t = ((centre.x - p.x) * dx + (centre.y - p.y) * dy) / (dx * dx + dy * dy)
            let foot = Point(x: p.x + t * dx, y: p.y + t * dy)
            out.append(Crease(a: centre, b: foot, fold: .valley, note: "hinge"))
        }
        return out
    }

    // MARK: - assembly

    static func build(points: [Point], activePairs: [(Int, Int)], leafNames: [String]) -> MoleculeReport {
        var notes: [String] = []
        let (verts, segs, corners, subNotes) = subdivide(points: points, activePairs: activePairs)
        notes.append(contentsOf: subNotes)

        if hasCrossing(verts, segs) {
            return MoleculeReport(faces: 0, filled: 0, unfilled: [], coverage: 0, creases: [],
                                  interiorVertices: [], kawasakiAllOK: false, mvAssigned: false,
                                  mvAllOK: false, crossingActivePaths: true,
                                  notes: notes + ["active paths cross each other; the subdivision is not planar, so no molecule decomposition was attempted"])
        }

        let fs = faces(verts, segs, corners: corners)
        var creases: [Crease] = []
        var filled = 0
        var filledArea = 0.0
        var unfilled: [(verts: [Int], reason: String)] = []

        for f in fs {
            let poly = f.verts.map { verts[$0] }
            if f.touchesPaperCorner && !f.allEdgesActive {
                unfilled.append((f.verts, "face has a paper corner that is not a leaf node; there is no flap to absorb it"))
                continue
            }
            guard let inc = inscribedCentre(poly) else {
                unfilled.append((f.verts, "no inscribed circle: a \(poly.count)-gon molecule with a gusset is required (not implemented)"))
                continue
            }
            if inc.residual > 1e-6 {
                unfilled.append((f.verts, String(format: "not a tangential polygon (residual %.2e): needs a gusset molecule", inc.residual)))
                continue
            }
            creases.append(contentsOf: moleculeCreases(poly, centre: inc.centre))
            filled += 1
            filledArea += f.area
        }

        // interior active paths become axial creases; a path that runs along the paper edge
        // is the edge of the sheet, not a fold
        func onBoundary(_ p: Point, _ q: Point) -> Bool {
            (abs(p.x) < 1e-9 && abs(q.x) < 1e-9) || (abs(p.x - 1) < 1e-9 && abs(q.x - 1) < 1e-9) ||
            (abs(p.y) < 1e-9 && abs(q.y) < 1e-9) || (abs(p.y - 1) < 1e-9 && abs(q.y - 1) < 1e-9)
        }
        for s in segs where s.kind == "active" {
            if onBoundary(verts[s.a], verts[s.b]) { continue }
            creases.append(Crease(a: verts[s.a], b: verts[s.b], fold: .mountain, note: "axial"))
        }

        _ = leafNames
        return MoleculeReport(faces: fs.count, filled: filled, unfilled: unfilled,
                              coverage: filledArea, creases: creases, interiorVertices: [],
                              kawasakiAllOK: false, mvAssigned: false, mvAllOK: false,
                              crossingActivePaths: false, notes: notes)
    }

    // MARK: - vertex collection and verification

    /// Creases from neighbouring molecules land in the interior of other creases (a hinge foot
    /// lands on an axial crease).  Split every crease at any vertex lying strictly inside it,
    /// otherwise the vertex degrees — and therefore the theorems — come out wrong.
    static func splitAtPoints(_ creases: [Crease]) -> [Crease] {
        var pts: [Point] = []
        func addPt(_ p: Point) {
            if !pts.contains(where: { hypot($0.x - p.x, $0.y - p.y) < 1e-9 }) { pts.append(p) }
        }
        for c in creases { addPt(c.a); addPt(c.b) }

        var out: [Crease] = []
        for c in creases {
            let dx = c.b.x - c.a.x, dy = c.b.y - c.a.y
            let len2 = dx * dx + dy * dy
            if len2 < 1e-18 { continue }
            var cuts: [(Double, Point)] = [(0, c.a), (1, c.b)]
            for p in pts {
                let t = ((p.x - c.a.x) * dx + (p.y - c.a.y) * dy) / len2
                if t <= 1e-9 || t >= 1 - 1e-9 { continue }
                let proj = Point(x: c.a.x + t * dx, y: c.a.y + t * dy)
                if hypot(proj.x - p.x, proj.y - p.y) < 1e-9 { cuts.append((t, p)) }
            }
            cuts.sort { $0.0 < $1.0 }
            for i in 0..<(cuts.count - 1) {
                let a = cuts[i].1, b = cuts[i + 1].1
                if hypot(a.x - b.x, a.y - b.y) > 1e-9 {
                    out.append(Crease(a: a, b: b, fold: c.fold, note: c.note))
                }
            }
        }
        // drop exact duplicates
        var seen = Set<String>()
        return out.filter { c in
            let k = [c.a.x, c.a.y, c.b.x, c.b.y].map { String(format: "%.9f", $0) }
            let key = (k[0] + k[1] < k[2] + k[3]) ? k.joined(separator: ",") : [k[2], k[3], k[0], k[1]].joined(separator: ",")
            if seen.contains(key) { return false }
            seen.insert(key); return true
        }
    }

    /// Backtracking search for an M/V assignment that satisfies Maekawa and the crimp test at
    /// every interior vertex.  Returns nil if no assignment is found within the node budget.
    static func assignMV(_ creases: [Crease], budget: Int = 4_000_000) -> [Fold]? {
        let verts = interiorVertices(creases)
        if verts.isEmpty { return creases.map { $0.fold } }

        // incidence: for each interior vertex, the creases meeting it with their directions
        var incident: [[(crease: Int, angle: Double)]] = []
        for v in verts {
            var list: [(Int, Double)] = []
            for (i, c) in creases.enumerated() {
                if hypot(c.a.x - v.x, c.a.y - v.y) < 1e-9 {
                    list.append((i, atan2(c.b.y - v.y, c.b.x - v.x)))
                } else if hypot(c.b.x - v.x, c.b.y - v.y) < 1e-9 {
                    list.append((i, atan2(c.a.y - v.y, c.a.x - v.x)))
                }
            }
            list.sort { $0.1 < $1.1 }
            incident.append(list.map { (crease: $0.0, angle: $0.1) })
        }
        var sectorsAt: [[Double]] = []
        for list in incident {
            var s: [Double] = []
            for i in 0..<list.count {
                var d = list[(i + 1) % list.count].angle - list[i].angle
                while d <= 0 { d += 2 * .pi }
                s.append(d * 180 / .pi)
            }
            sectorsAt.append(s)
        }

        // order creases so that each vertex completes as early as possible
        var order: [Int] = []
        var placed = Set<Int>()
        let byDegree = incident.indices.sorted { incident[$0].count < incident[$1].count }
        for vi in byDegree {
            for e in incident[vi] where !placed.contains(e.crease) {
                placed.insert(e.crease); order.append(e.crease)
            }
        }
        for i in creases.indices where !placed.contains(i) { order.append(i) }
        var position = [Int](repeating: -1, count: creases.count)
        for (k, c) in order.enumerated() { position[c] = k }
        // vertex -> the step at which its last crease becomes assigned
        var completesAt: [Int: [Int]] = [:]
        for (vi, list) in incident.enumerated() {
            let last = list.map { position[$0.crease] }.max() ?? 0
            completesAt[last, default: []].append(vi)
        }

        var assign = [Int](repeating: 0, count: creases.count)
        var nodes = 0
        var solution: [Int]? = nil

        func check(_ vi: Int) -> Bool {
            let mv = incident[vi].map { assign[$0.crease] }
            let m = mv.filter { $0 == 1 }.count
            if abs(m - (mv.count - m)) != 2 { return false }
            return Origami.mvFlatFoldable(sectors: sectorsAt[vi], mv: mv)
        }

        func rec(_ k: Int) {
            if solution != nil || nodes > budget { return }
            nodes += 1
            if k == order.count { solution = assign; return }
            for val in [-1, 1] {
                assign[order[k]] = val
                var ok = true
                for vi in completesAt[k] ?? [] where !check(vi) { ok = false; break }
                if ok { rec(k + 1) }
                if solution != nil { return }
            }
            assign[order[k]] = 0
        }
        rec(0)
        guard let s = solution else { return nil }
        return s.map { $0 == 1 ? Fold.mountain : Fold.valley }
    }

    /// Every point where two or more creases meet, that is not on the paper boundary.
    static func interiorVertices(_ creases: [Crease]) -> [Point] {
        var pts: [Point] = []
        func add(_ p: Point) {
            if p.x < 1e-9 || p.x > 1 - 1e-9 || p.y < 1e-9 || p.y > 1 - 1e-9 { return }
            if !pts.contains(where: { hypot($0.x - p.x, $0.y - p.y) < 1e-9 }) { pts.append(p) }
        }
        for c in creases { add(c.a); add(c.b) }
        return pts
    }
}
