// SVG.swift — drawing helpers.  Nothing here decides anything; it only renders results
// that have already been computed and checked elsewhere.

import Foundation

enum SVG {

    static func f(_ v: Double) -> String { String(format: "%.5f", v) }

    /// Circle/packing diagram for a solved tree packing.  This is NOT a crease pattern.
    static func packingDiagram(_ r: PackingResult, radii: [Double], title: String,
                               side: Double = 620, pad: Double = 60) -> String {
        var s = ""
        let W = side + 2 * pad
        s += "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(f(W))\" height=\"\(f(W + 34))\" viewBox=\"0 0 \(f(W)) \(f(W + 34))\">\n"
        s += "<rect width=\"100%\" height=\"100%\" fill=\"#ffffff\"/>\n"
        s += "<text x=\"\(f(pad))\" y=\"28\" font-family=\"sans-serif\" font-size=\"16\" fill=\"#111\">\(esc(title))</text>\n"
        func X(_ x: Double) -> Double { pad + x * side }
        func Y(_ y: Double) -> Double { pad + 34 + (1 - y) * side }
        s += "<rect x=\"\(f(pad))\" y=\"\(f(pad + 34))\" width=\"\(f(side))\" height=\"\(f(side))\" fill=\"none\" stroke=\"#111\" stroke-width=\"2\"/>\n"
        // active constraints
        for (i, j) in r.activePairs {
            s += "<line x1=\"\(f(X(r.points[i].x)))\" y1=\"\(f(Y(r.points[i].y)))\" x2=\"\(f(X(r.points[j].x)))\" y2=\"\(f(Y(r.points[j].y)))\" stroke=\"#c00\" stroke-width=\"1.4\" stroke-dasharray=\"5 4\"/>\n"
        }
        for (k, p) in r.points.enumerated() {
            let rad = radii[k] * side
            s += "<circle cx=\"\(f(X(p.x)))\" cy=\"\(f(Y(p.y)))\" r=\"\(f(rad))\" fill=\"#2b6cb0\" fill-opacity=\"0.10\" stroke=\"#2b6cb0\" stroke-width=\"1.2\"/>\n"
            s += "<circle cx=\"\(f(X(p.x)))\" cy=\"\(f(Y(p.y)))\" r=\"3.2\" fill=\"#2b6cb0\"/>\n"
            s += "<text x=\"\(f(X(p.x) + 7))\" y=\"\(f(Y(p.y) - 7))\" font-family=\"sans-serif\" font-size=\"12\" fill=\"#123\">\(esc(r.leafNames[k]))</text>\n"
        }
        s += "</svg>\n"
        return s
    }

    /// Crease pattern.  Mountain = solid red, valley = dashed blue, paper edge = black.
    static func creasePattern(_ creases: [Crease], title: String,
                              side: Double = 620, pad: Double = 60) -> String {
        var s = ""
        let W = side + 2 * pad
        s += "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(f(W))\" height=\"\(f(W + 60))\" viewBox=\"0 0 \(f(W)) \(f(W + 60))\">\n"
        s += "<rect width=\"100%\" height=\"100%\" fill=\"#ffffff\"/>\n"
        s += "<text x=\"\(f(pad))\" y=\"28\" font-family=\"sans-serif\" font-size=\"16\" fill=\"#111\">\(esc(title))</text>\n"
        func X(_ x: Double) -> Double { pad + x * side }
        func Y(_ y: Double) -> Double { pad + 34 + (1 - y) * side }
        s += "<rect x=\"\(f(pad))\" y=\"\(f(pad + 34))\" width=\"\(f(side))\" height=\"\(f(side))\" fill=\"none\" stroke=\"#111\" stroke-width=\"2.5\"/>\n"
        for c in creases {
            let col = c.fold == .mountain ? "#d02020" : "#2050d0"
            let dash = c.fold == .mountain ? "" : " stroke-dasharray=\"9 6\""
            s += "<line x1=\"\(f(X(c.a.x)))\" y1=\"\(f(Y(c.a.y)))\" x2=\"\(f(X(c.b.x)))\" y2=\"\(f(Y(c.b.y)))\" stroke=\"\(col)\" stroke-width=\"2.2\"\(dash)/>\n"
        }
        let ly = pad + 34 + side + 30
        s += "<line x1=\"\(f(pad))\" y1=\"\(f(ly))\" x2=\"\(f(pad + 38))\" y2=\"\(f(ly))\" stroke=\"#d02020\" stroke-width=\"2.2\"/>\n"
        s += "<text x=\"\(f(pad + 46))\" y=\"\(f(ly + 4))\" font-family=\"sans-serif\" font-size=\"13\" fill=\"#111\">mountain (山折り)</text>\n"
        s += "<line x1=\"\(f(pad + 190))\" y1=\"\(f(ly))\" x2=\"\(f(pad + 228))\" y2=\"\(f(ly))\" stroke=\"#2050d0\" stroke-width=\"2.2\" stroke-dasharray=\"9 6\"/>\n"
        s += "<text x=\"\(f(pad + 236))\" y=\"\(f(ly + 4))\" font-family=\"sans-serif\" font-size=\"13\" fill=\"#111\">valley (谷折り)</text>\n"
        s += "</svg>\n"
        return s
    }

    static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
    }
}
