// ElmParse.swift
// Purely syntactic extraction of module / import / line-count facts from Elm sources.
// No Elm compiler is used: this is a line-oriented scanner, and every heuristic it
// applies is reported as such in the output.

import Foundation

struct ImportDecl {
    var module: String
    var alias: String?
    var exposed: [String]   // names listed in `exposing (...)`; `X(..)` is recorded as "X(..)"
    var exposesAll: Bool    // `exposing (..)`
    var line: Int
}

struct ElmModule {
    var name: String
    var path: String
    var totalLines: Int
    var blankLines: Int
    var commentLines: Int
    var literalLines: Int   // lines strictly inside a """ ... """ block
    var codeLines: Int      // total - blank - comment - literal
    var imports: [ImportDecl]
    var unionConstructors: [String: [String]]  // `type Route = Home | Post Int` -> ["Route": ["Home","Post"]]
    var bodyWords: Set<String>                 // identifier-ish tokens outside module/import lines
}

enum ElmParse {

    static func tokenizeWords(_ s: String) -> [String] {
        var out: [String] = []
        var cur = ""
        for ch in s {
            if ch.isLetter || ch.isNumber || ch == "_" || ch == "." {
                cur.append(ch)
            } else {
                if !cur.isEmpty { out.append(cur); cur = "" }
            }
        }
        if !cur.isEmpty { out.append(cur) }
        return out
    }

    static func parse(path: String, text: String) -> ElmModule {
        let rawLines = text.components(separatedBy: "\n")

        var name = "?"
        var imports: [ImportDecl] = []
        var blank = 0, comment = 0, literal = 0
        var inLiteral = false
        var inBlockComment = false
        var bodyWords = Set<String>()
        var unionCtors: [String: [String]] = [:]

        // Buffer for multi-line `type X = A | B` declarations.
        var pendingTypeName: String? = nil
        var pendingTypeBuf = ""

        func flushPendingType() {
            guard let tn = pendingTypeName else { return }
            // Split on '|' and take the leading token of each alternative.
            let parts = pendingTypeBuf.components(separatedBy: "|")
            var ctors: [String] = []
            for p in parts {
                if let first = tokenizeWords(p).first, let c = first.first, c.isUppercase {
                    ctors.append(first)
                }
            }
            if !ctors.isEmpty { unionCtors[tn] = ctors }
            pendingTypeName = nil
            pendingTypeBuf = ""
        }

        for (idx, raw) in rawLines.enumerated() {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)

            // --- triple-quoted string tracking (counted before anything else) ---
            let tripleCount = countOccurrences(raw, of: "\"\"\"")
            let wasInLiteral = inLiteral
            if tripleCount % 2 == 1 { inLiteral.toggle() }
            if wasInLiteral && inLiteral {
                // fully inside a literal block
                literal += 1
                continue
            }
            if wasInLiteral && !inLiteral {
                // closing line of a literal block: counts as code (it carries the closing quotes)
                continue
            }

            if trimmed.isEmpty { blank += 1; continue }

            // --- block comments {- -} ---
            if inBlockComment {
                comment += 1
                if raw.contains("-}") { inBlockComment = false }
                continue
            }
            if trimmed.hasPrefix("{-") {
                comment += 1
                if !raw.contains("-}") { inBlockComment = true }
                continue
            }
            if trimmed.hasPrefix("--") { comment += 1; continue }

            // --- module declaration ---
            if trimmed.hasPrefix("module ") || trimmed.hasPrefix("port module ") {
                let w = tokenizeWords(trimmed)
                // ["module","Page","About", ...] -> the dotted name is kept intact by tokenizer
                if let i = w.firstIndex(of: "module"), i + 1 < w.count { name = w[i + 1] }
                continue
            }

            // --- imports ---
            if trimmed.hasPrefix("import ") {
                let w = tokenizeWords(trimmed)
                guard w.count >= 2 else { continue }
                let mod = w[1]
                var alias: String? = nil
                if let ai = w.firstIndex(of: "as"), ai + 1 < w.count { alias = w[ai + 1] }
                var exposed: [String] = []
                var all = false
                if let r = trimmed.range(of: "exposing") {
                    let tail = String(trimmed[r.upperBound...])
                    if tail.replacingOccurrences(of: " ", with: "").contains("(..)")
                        && tail.replacingOccurrences(of: " ", with: "").hasPrefix("((..)") == false
                        && tail.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "") == "(..)" {
                        all = true
                    }
                    // record each exposed entry, marking `X(..)` forms
                    let inner = tail.replacingOccurrences(of: "(..)", with: "@ALL@")
                    for piece in inner.components(separatedBy: ",") {
                        let toks = tokenizeWords(piece)
                        if let t = toks.first {
                            if piece.contains("@ALL@") { exposed.append("\(t)(..)") } else { exposed.append(t) }
                        }
                    }
                    if all { exposed = [] }
                }
                imports.append(ImportDecl(module: mod, alias: alias, exposed: exposed,
                                          exposesAll: all, line: idx + 1))
                continue
            }

            // --- union type declarations (possibly multi-line) ---
            if trimmed.hasPrefix("type ") && !trimmed.hasPrefix("type alias") {
                flushPendingType()
                let w = tokenizeWords(trimmed)
                if w.count >= 2 { pendingTypeName = w[1] }
                if let eq = trimmed.range(of: "=") {
                    pendingTypeBuf = String(trimmed[eq.upperBound...])
                }
                for t in tokenizeWords(trimmed) { bodyWords.insert(t) }
                continue
            }
            if pendingTypeName != nil {
                if trimmed.hasPrefix("|") || trimmed.hasPrefix("=") {
                    pendingTypeBuf += " | " + trimmed
                    for t in tokenizeWords(trimmed) { bodyWords.insert(t) }
                    continue
                } else {
                    flushPendingType()
                }
            }

            for t in tokenizeWords(trimmed) { bodyWords.insert(t) }
        }
        flushPendingType()

        let total = rawLines.count
        let code = total - blank - comment - literal
        return ElmModule(name: name, path: path, totalLines: total, blankLines: blank,
                         commentLines: comment, literalLines: literal, codeLines: code,
                         imports: imports, unionConstructors: unionCtors, bodyWords: bodyWords)
    }

    static func countOccurrences(_ s: String, of sub: String) -> Int {
        var n = 0
        var r = s.startIndex..<s.endIndex
        while let f = s.range(of: sub, range: r) {
            n += 1
            r = f.upperBound..<s.endIndex
        }
        return n
    }

    /// Heuristic: is `imp` referenced anywhere in the body of `m`?
    /// Returns nil when the heuristic cannot decide (e.g. `exposing (..)`).
    static func importLooksUsed(_ imp: ImportDecl, in m: ElmModule,
                                allModules: [String: ElmModule]) -> Bool? {
        if imp.exposesAll { return nil }  // cannot decide without name resolution

        // 1. qualified use: "Route.parseUrl" or alias "Articles.all"
        let qualifiers = [imp.alias, imp.module, imp.module.components(separatedBy: ".").last]
            .compactMap { $0 }
        for w in m.bodyWords {
            for q in qualifiers where w.hasPrefix(q + ".") { return true }
            if qualifiers.contains(w) { return true }
        }

        // 2. unqualified use of an exposed name; expand `X(..)` via the source module
        var names: [String] = []
        for e in imp.exposed {
            if e.hasSuffix("(..)") {
                let tname = String(e.dropLast(4))
                names.append(tname)
                if let src = allModules[imp.module], let cs = src.unionConstructors[tname] {
                    names.append(contentsOf: cs)
                }
            } else {
                names.append(e)
            }
        }
        if names.isEmpty { return nil }
        for n in names where m.bodyWords.contains(n) { return true }
        return false
    }
}
