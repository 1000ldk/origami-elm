// Origami.swift
// Geometric verification: Kawasaki, Maekawa, and single-vertex flat-foldability of an
// explicit M/V assignment (via the crimp / big-little-big reduction).
//
// Everything here operates on actual coordinates.  Nothing is asserted about a crease
// pattern that has not been run through these checks.

import Foundation

enum Fold: Int { case mountain = 1, valley = -1 }

struct Crease {
    var a: Point
    var b: Point
    var fold: Fold
    var note: String = ""
}

struct VertexCheck {
    var at: Point
    var degree: Int
    var sectors: [Double]         // degrees, cyclic
    var kawasakiAlternatingSum: Double
    var kawasakiOK: Bool
    var mountains: Int
    var valleys: Int
    var maekawaOK: Bool
    var mvFoldable: Bool          // crimp reduction succeeded
}

enum Origami {

    // MARK: - single-vertex flat-foldability of a given M/V assignment

    /// `sectors[i]` is the angle (degrees) between crease i and crease i+1 (cyclic).
    /// `mv[i]` is the assignment of crease i.
    /// Returns true iff the crimp reduction succeeds, which decides flat-foldability
    /// of a single vertex with a given M/V assignment.
    static func mvFlatFoldable(sectors: [Double], mv: [Int], tol: Double = 1e-7) -> Bool {
        var a = sectors
        var f = mv
        guard a.count == f.count, a.count >= 2 else { return false }
        // An odd-degree interior vertex can never be flat-folded (Maekawa needs |M-V| = 2 with
        // M + V odd, which is impossible), and the crimp reduction is only defined for even
        // degree, so reject it here rather than reducing into an inconsistent state.
        guard a.count % 2 == 0 else { return false }

        while a.count > 2 {
            let n = a.count
            var chosen = -1
            // prefer a strictly locally minimal sector; fall back to a weakly minimal one
            for pass in 0..<2 {
                for i in 0..<n {
                    let prev = a[(i - 1 + n) % n], next = a[(i + 1) % n]
                    let strictly = a[i] < prev - tol && a[i] < next - tol
                    let weakly = a[i] <= prev + tol && a[i] <= next + tol
                    let ok = (pass == 0) ? strictly : weakly
                    if ok && f[i] != f[(i + 1) % n] { chosen = i; break }
                }
                if chosen >= 0 { break }
            }
            if chosen < 0 { return false }

            // Crimp sector `i`: creases i and i+1 disappear, sectors i-1, i, i+1 merge
            // into a single sector of size a[i-1] - a[i] + a[i+1].
            let i = chosen
            let merged = a[(i - 1 + n) % n] - a[i] + a[(i + 1) % n]
            if merged < -tol { return false }

            // Rebuild starting from crease i+2, walking cyclically back to crease i-1.
            var nf: [Int] = []
            for k in 0..<(n - 2) { nf.append(f[(i + 2 + k) % n]) }
            var na: [Double] = []
            for k in 0..<(n - 3) { na.append(a[(i + 2 + k) % n]) }
            na.append(merged)   // sector between crease i-1 (last kept) and crease i+2 (first kept)

            a = na
            f = nf
        }

        // terminal: a cone with two creases; foldable iff the two sectors are equal and
        // the two creases fold the same way (they are the two halves of one straight fold).
        return abs(a[0] - a[1]) < 1e-6 && f[0] == f[1]
    }

    // MARK: - vertex geometry

    static func analyseVertex(at v: Point, creases: [Crease], tol: Double = 1e-9) -> VertexCheck? {
        var dirs: [(Double, Fold)] = []
        for c in creases {
            if hypot(c.a.x - v.x, c.a.y - v.y) < 1e-9 {
                dirs.append((atan2(c.b.y - v.y, c.b.x - v.x) * 180 / .pi, c.fold))
            } else if hypot(c.b.x - v.x, c.b.y - v.y) < 1e-9 {
                dirs.append((atan2(c.a.y - v.y, c.a.x - v.x) * 180 / .pi, c.fold))
            }
        }
        guard dirs.count >= 2 else { return nil }
        dirs.sort { ($0.0 < 0 ? $0.0 + 360 : $0.0) < ($1.0 < 0 ? $1.0 + 360 : $1.0) }
        let n = dirs.count
        var sectors: [Double] = []
        for i in 0..<n {
            var d = dirs[(i + 1) % n].0 - dirs[i].0
            while d <= 0 { d += 360 }
            sectors.append(d)
        }
        var alt = 0.0
        for (i, s) in sectors.enumerated() { alt += (i % 2 == 0 ? s : -s) }
        let m = dirs.filter { $0.1 == .mountain }.count
        let val = n - m
        let mv = dirs.map { $0.1 == .mountain ? 1 : -1 }
        return VertexCheck(at: v, degree: n, sectors: sectors,
                           kawasakiAlternatingSum: alt,
                           kawasakiOK: n % 2 == 0 && abs(alt) < 1e-7,
                           mountains: m, valleys: val,
                           maekawaOK: abs(m - val) == 2,
                           mvFoldable: mvFlatFoldable(sectors: sectors, mv: mv))
    }

    // MARK: - the square molecule (4 corner flaps, all four edges active)

    /// Universal molecule of the unit square whose four corners are leaf vertices with
    /// all four edges active.  The inset polygon degenerates to the centre at t = 1/2,
    /// so the molecule is: four corner bisectors (the diagonals) + four hinge creases
    /// from the centre perpendicular to each side.
    static func squareMolecule(mv: [Int]) -> [Crease] {
        let c = Point(x: 0.5, y: 0.5)
        // order matters: this is the cyclic order used by `mv`, starting at 0 degrees
        let targets: [(Point, String)] = [
            (Point(x: 1.0, y: 0.5), "hinge -> midpoint of right edge"),
            (Point(x: 1.0, y: 1.0), "bisector -> corner (1,1)"),
            (Point(x: 0.5, y: 1.0), "hinge -> midpoint of top edge"),
            (Point(x: 0.0, y: 1.0), "bisector -> corner (0,1)"),
            (Point(x: 0.0, y: 0.5), "hinge -> midpoint of left edge"),
            (Point(x: 0.0, y: 0.0), "bisector -> corner (0,0)"),
            (Point(x: 0.5, y: 0.0), "hinge -> midpoint of bottom edge"),
            (Point(x: 1.0, y: 0.0), "bisector -> corner (1,0)")
        ]
        var out: [Crease] = []
        for (i, t) in targets.enumerated() {
            out.append(Crease(a: c, b: t.0, fold: mv[i] == 1 ? .mountain : .valley, note: t.1))
        }
        return out
    }

    /// All M/V assignments of the square molecule that pass the crimp test.
    static func squareMoleculeValidAssignments() -> [[Int]] {
        var ok: [[Int]] = []
        let sectors = [Double](repeating: 45.0, count: 8)
        for bits in 0..<256 {
            var mv = [Int](repeating: 0, count: 8)
            for i in 0..<8 { mv[i] = ((bits >> i) & 1) == 1 ? 1 : -1 }
            if mvFlatFoldable(sectors: sectors, mv: mv) { ok.append(mv) }
        }
        return ok
    }

    // MARK: - self-test of the checker against a textbook case

    /// Degree-4 vertex, all sectors 90 degrees.  Textbook result: exactly the eight
    /// assignments with three creases of one kind and one of the other are flat-foldable.
    static func selfTestDegree4() -> (accepted: Int, expected: Int, detail: String) {
        var acc = 0
        var byCount: [Int: Int] = [:]
        for bits in 0..<16 {
            var mv = [Int](repeating: 0, count: 4)
            for i in 0..<4 { mv[i] = ((bits >> i) & 1) == 1 ? 1 : -1 }
            if mvFlatFoldable(sectors: [90, 90, 90, 90], mv: mv) {
                acc += 1
                byCount[mv.filter { $0 == 1 }.count, default: 0] += 1
            }
        }
        let d = byCount.keys.sorted().map { "M=\($0):\(byCount[$0]!)" }.joined(separator: ", ")
        return (acc, 8, d)
    }
}
