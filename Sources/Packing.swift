// Packing.swift
// Lang's tree theorem, numerically.
//
// THEOREM (Lang 1996, "A computational algorithm for origami design";
//          Lang, "Origami Design Secrets", ch. on the tree method):
//   A uniaxial base whose flap structure is the weighted tree T can be folded from a
//   square of side s if and only if there is an assignment of the leaf nodes of T to
//   points u_i in the square with
//        || u_i - u_j ||_2  >=  s * m * d_T(i, j)     for every pair of leaves i, j,
//   where d_T is the weighted path length in T and m is the scale.  Existence of a
//   flat-foldable crease pattern for such a placement is then guaranteed by the
//   Universal Molecule theorem.
//
// So the *feasibility* question has a clean numerical form: find the largest m for
// which such a placement exists.  This file maximises
//        m(u) = min_{i<j} || u_i - u_j || / d_T(i,j)
// over u in [0,1]^{2n} by soft-min gradient ascent with random restarts, and then
// VERIFIES the returned placement by evaluating every constraint exactly.
//
// Any m we return is therefore a *certified lower bound* on the optimum: the placement
// is checked, so a base with that scale provably exists.  We do NOT claim global
// optimality (the problem is non-convex; this is the same situation as TreeMaker's own
// optimiser).

import Foundation

struct Point { var x: Double; var y: Double }

struct PackingResult {
    var points: [Point]
    var leafNames: [String]
    var scale: Double          // m
    var minSlack: Double       // min over pairs of (dist - m*d_T)  -> ~0 by construction
    var feasible: Bool
    var activePairs: [(Int, Int)]   // pairs at (numerically) zero slack
    var restartsUsed: Int
}

struct Xorshift {
    var s: UInt64
    init(seed: UInt64) { s = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    mutating func next() -> UInt64 {
        s ^= s << 13; s ^= s >> 7; s ^= s << 17; return s
    }
    mutating func unit() -> Double { Double(next() >> 11) * (1.0 / 9007199254740992.0) }
}

enum Packing {

    /// One pass of constraint projection: every violated pair is pushed apart until it
    /// satisfies || u_i - u_j || >= m * d_ij, then every point is clamped back into the
    /// square.  Returns the largest remaining violation.
    static func project(_ p: inout [Point], _ dmat: [[Double]], _ m: Double,
                        iters: Int, rng: inout Xorshift, fixed: [Int: Point] = [:]) -> Double {
        let n = p.count
        var worst = Double.infinity
        for _ in 0..<iters {
            worst = 0
            for i in 0..<n {
                for j in (i + 1)..<n {
                    let need = m * dmat[i][j]
                    var dx = p[i].x - p[j].x, dy = p[i].y - p[j].y
                    var d = (dx * dx + dy * dy).squareRoot()
                    if d < 1e-12 {
                        dx = rng.unit() - 0.5; dy = rng.unit() - 0.5
                        d = max((dx * dx + dy * dy).squareRoot(), 1e-12)
                    }
                    let viol = need - d
                    if viol > 0 {
                        worst = max(worst, viol)
                        // over-relax slightly; this escapes shallow jams faster
                        let push = 0.55 * viol / d
                        p[i].x += push * dx; p[i].y += push * dy
                        p[j].x -= push * dx; p[j].y -= push * dy
                    }
                }
            }
            for i in 0..<n {
                p[i].x = min(1.0, max(0.0, p[i].x))
                p[i].y = min(1.0, max(0.0, p[i].y))
            }
            for (i, pt) in fixed { p[i] = pt }
            if worst < 1e-12 { break }
        }
        return worst
    }

    /// Grow the scale as far as projection can still reach a feasible configuration.
    static func inflate(_ p: inout [Point], _ dmat: [[Double]],
                        steps: Int, rng: inout Xorshift, fixed: [Int: Point] = [:]) -> Double {
        var best = exactScale(p, dmat)
        var bestP = p
        var step = 0.03
        var used = 0
        while step > 1e-7 && used < steps {
            let target = best * (1 + step)
            var success = false
            for attempt in 0..<4 {
                used += 1
                var trial = bestP
                if attempt > 0 {
                    let mag = 0.015 * Double(attempt)
                    for i in 0..<trial.count where fixed[i] == nil {
                        trial[i].x = min(1, max(0, trial[i].x + (rng.unit() - 0.5) * mag))
                        trial[i].y = min(1, max(0, trial[i].y + (rng.unit() - 0.5) * mag))
                    }
                }
                let w = project(&trial, dmat, target, iters: 300, rng: &rng, fixed: fixed)
                if w < 1e-10 {
                    let s = exactScale(trial, dmat)
                    if s > best { best = s; bestP = trial; success = true; break }
                }
                if used >= steps { break }
            }
            step = success ? min(step * 1.3, 0.06) : step * 0.5
        }
        p = bestP
        return best
    }

    /// Maximising the scale leaves the configuration under-constrained: only a handful of
    /// constraints end up tight, so the active-path graph is too sparse to cut the paper into
    /// polygons.  This pulls every slack pair together, re-projecting to keep feasibility, until
    /// the packing is as rigid as it can be at the same scale.  The scale never decreases.
    static func compact(_ p: inout [Point], _ dmat: [[Double]], _ m: Double,
                        fixed: [Int: Point], iters: Int, rng: inout Xorshift) {
        let n = p.count
        var best = p
        for _ in 0..<iters {
            var q = best
            // attraction proportional to slack
            var fx = [Double](repeating: 0, count: n)
            var fy = [Double](repeating: 0, count: n)
            for i in 0..<n {
                for j in (i + 1)..<n {
                    let dx = q[i].x - q[j].x, dy = q[i].y - q[j].y
                    let d = max(hypot(dx, dy), 1e-12)
                    let slack = d - m * dmat[i][j]
                    if slack > 0 {
                        let c = 0.05 * slack / d
                        fx[i] -= c * dx; fy[i] -= c * dy
                        fx[j] += c * dx; fy[j] += c * dy
                    }
                }
            }
            for i in 0..<n where fixed[i] == nil {
                q[i].x = min(1, max(0, q[i].x + fx[i]))
                q[i].y = min(1, max(0, q[i].y + fy[i]))
            }
            for (i, pt) in fixed { q[i] = pt }
            let w = project(&q, dmat, m, iters: 400, rng: &rng, fixed: fixed)
            if w < 1e-10 && exactScale(q, dmat) >= m - 1e-12 { best = q }
        }
        p = best
    }

    /// dmat[i][j] = required tree distance between leaves i and j (unscaled).
    /// `fixed` pins chosen leaves to given points (used to place flaps at the paper corners).
    static func optimise(dmat: [[Double]], leafNames: [String],
                         restarts: Int = 240, iters: Int = 6000,
                         seed: UInt64 = 0xC0FFEE,
                         fixed: [Int: Point] = [:],
                         compactAfter: Bool = true) -> PackingResult {
        let n = dmat.count
        precondition(n >= 2)
        var rng = Xorshift(seed: seed)

        var bestPts: [Point] = []
        var bestScale = -1.0

        for _ in 0..<restarts {
            var p = (0..<n).map { _ in Point(x: rng.unit(), y: rng.unit()) }
            for (i, pt) in fixed { p[i] = pt }

            for it in 0..<iters {
                let t = Double(it) / Double(iters - 1)
                // beta: soft-min sharpness, annealed up.  eta: step size, annealed down.
                let beta = 8.0 * pow(4000.0 / 8.0, t)
                let eta = 0.06 * pow(0.002 / 0.06, t)

                // ratios r_ij = dist_ij / d_ij
                var rmin = Double.infinity
                var rs = [Double](repeating: 0, count: n * n)
                for i in 0..<n {
                    for j in (i + 1)..<n {
                        let dx = p[i].x - p[j].x, dy = p[i].y - p[j].y
                        let d = (dx * dx + dy * dy).squareRoot()
                        let r = d / dmat[i][j]
                        rs[i * n + j] = r
                        if r < rmin { rmin = r }
                    }
                }
                // soft-min weights
                var wsum = 0.0
                var ws = [Double](repeating: 0, count: n * n)
                for i in 0..<n {
                    for j in (i + 1)..<n {
                        let w = exp(-beta * (rs[i * n + j] - rmin))
                        ws[i * n + j] = w
                        wsum += w
                    }
                }
                if wsum <= 0 { break }

                var gx = [Double](repeating: 0, count: n)
                var gy = [Double](repeating: 0, count: n)
                for i in 0..<n {
                    for j in (i + 1)..<n {
                        let w = ws[i * n + j] / wsum
                        let dx = p[i].x - p[j].x, dy = p[i].y - p[j].y
                        let d = max((dx * dx + dy * dy).squareRoot(), 1e-12)
                        let c = w / (dmat[i][j] * d)
                        gx[i] += c * dx; gy[i] += c * dy
                        gx[j] -= c * dx; gy[j] -= c * dy
                    }
                }
                for i in 0..<n where fixed[i] == nil {
                    p[i].x = min(1.0, max(0.0, p[i].x + eta * gx[i]))
                    p[i].y = min(1.0, max(0.0, p[i].y + eta * gy[i]))
                }
            }

            // polish: projection + inflation, which is far better than gradient ascent at
            // pushing points onto the boundary and into corners
            var q = p
            let s = inflate(&q, dmat, steps: 400, rng: &rng, fixed: fixed)
            if s > bestScale { bestScale = s; bestPts = q }

            // also try a corner-seeded start, which is where good packings usually live
            var c = (0..<n).map { _ in Point(x: rng.unit(), y: rng.unit()) }
            let corners = [Point(x: 0, y: 0), Point(x: 1, y: 0), Point(x: 1, y: 1), Point(x: 0, y: 1)]
            for k in 0..<min(4, n) where fixed[k] == nil { c[k] = corners[k] }
            for (i, pt) in fixed { c[i] = pt }
            _ = project(&c, dmat, exactScale(c, dmat), iters: 100, rng: &rng, fixed: fixed)
            let s2 = inflate(&c, dmat, steps: 400, rng: &rng, fixed: fixed)
            if s2 > bestScale { bestScale = s2; bestPts = c }
        }

        if compactAfter && bestScale > 0 {
            compact(&bestPts, dmat, bestScale, fixed: fixed, iters: 60, rng: &rng)
        }

        // --- verification pass: recompute every constraint from scratch ---
        let m = exactScale(bestPts, dmat)
        var minSlack = Double.infinity
        var active: [(Int, Int)] = []
        for i in 0..<n {
            for j in (i + 1)..<n {
                let dx = bestPts[i].x - bestPts[j].x, dy = bestPts[i].y - bestPts[j].y
                let d = (dx * dx + dy * dy).squareRoot()
                let slack = d - m * dmat[i][j]
                minSlack = min(minSlack, slack)
                if slack < 1e-6 * max(1.0, d) { active.append((i, j)) }
            }
        }
        var inBox = true
        for q in bestPts where q.x < -1e-9 || q.x > 1 + 1e-9 || q.y < -1e-9 || q.y > 1 + 1e-9 {
            _ = q; inBox = false
        }
        return PackingResult(points: bestPts, leafNames: leafNames, scale: m,
                             minSlack: minSlack, feasible: inBox && minSlack > -1e-9,
                             activePairs: active, restartsUsed: restarts)
    }

    static func exactScale(_ p: [Point], _ dmat: [[Double]]) -> Double {
        let n = p.count
        var m = Double.infinity
        for i in 0..<n {
            for j in (i + 1)..<n {
                let dx = p[i].x - p[j].x, dy = p[i].y - p[j].y
                let d = (dx * dx + dy * dy).squareRoot()
                m = min(m, d / dmat[i][j])
            }
        }
        return m
    }
}
