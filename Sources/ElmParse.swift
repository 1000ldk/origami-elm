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

/// A top-level value declaration, with its measured extent.
struct ElmDecl {
    var name: String
    var annotation: String?    // text after `name :`, if a type annotation was present
    var startLine: Int         // 1-based, the annotation line if there is one
    var endLine: Int
    var codeLines: Int         // non-blank, non-comment, non-string-literal lines in the block
    var isExposed: Bool
    /// true when the declaration's return type is Html / Browser.Document, i.e. it renders.
    var rendersHtml: Bool
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
    var exposed: [String]                      // names in `module X exposing (...)`
    var exposesAll: Bool
    var decls: [ElmDecl]

    /// Declarations that render, are exposed, and are therefore candidate leaves.
    var viewDecls: [ElmDecl] { decls.filter { $0.rendersHtml } }
    var viewLOC: Int { viewDecls.reduce(0) { $0 + $1.codeLines } }
    /// Code lines not accounted for by any rendering declaration.
    var nonViewLOC: Int { max(0, codeLines - viewLOC) }
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

    /// Per-line classification, used both for counting and for measuring declarations.
    enum LineKind: Int { case code = 0, blank, comment, literal }

    static func parse(path: String, text: String) -> ElmModule {
        let rawLines = text.components(separatedBy: "\n")
        var kinds = [LineKind](repeating: .code, count: rawLines.count)

        var name = "?"
        var moduleExposed: [String] = []
        var moduleExposesAll = false
        var moduleHeaderEnd = 0     // last line index belonging to the `module ... exposing (...)` header
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
                kinds[idx] = .literal
                continue
            }
            if wasInLiteral && !inLiteral {
                // closing line of a literal block: counts as code (it carries the closing quotes)
                continue
            }

            if trimmed.isEmpty { blank += 1; kinds[idx] = .blank; continue }

            // --- block comments {- -} ---
            if inBlockComment {
                comment += 1
                kinds[idx] = .comment
                if raw.contains("-}") { inBlockComment = false }
                continue
            }
            if trimmed.hasPrefix("{-") {
                comment += 1
                kinds[idx] = .comment
                if !raw.contains("-}") { inBlockComment = true }
                continue
            }
            if trimmed.hasPrefix("--") { comment += 1; kinds[idx] = .comment; continue }

            // --- module declaration (the exposing list may wrap over several lines) ---
            if trimmed.hasPrefix("module ") || trimmed.hasPrefix("port module ") {
                let w = tokenizeWords(trimmed)
                // ["module","Page","About", ...] -> the dotted name is kept intact by tokenizer
                if let i = w.firstIndex(of: "module"), i + 1 < w.count { name = w[i + 1] }
                var header = trimmed
                var j = idx
                while ElmParse.countOccurrences(header, of: "(") > ElmParse.countOccurrences(header, of: ")"),
                      j + 1 < rawLines.count {
                    j += 1
                    header += " " + rawLines[j].trimmingCharacters(in: .whitespaces)
                }
                moduleHeaderEnd = j
                if let r = header.range(of: "exposing") {
                    let tail = String(header[r.upperBound...]).trimmingCharacters(in: .whitespaces)
                    if tail.replacingOccurrences(of: " ", with: "") == "(..)" {
                        moduleExposesAll = true
                    } else {
                        for piece in tail.components(separatedBy: ",") {
                            if let t = tokenizeWords(piece).first { moduleExposed.append(t) }
                        }
                    }
                }
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
        let decls = segmentDeclarations(rawLines: rawLines, kinds: kinds,
                                        startAfter: moduleHeaderEnd,
                                        exposed: moduleExposed, exposesAll: moduleExposesAll)
        return ElmModule(name: name, path: path, totalLines: total, blankLines: blank,
                         commentLines: comment, literalLines: literal, codeLines: code,
                         imports: imports, unionConstructors: unionCtors, bodyWords: bodyWords,
                         exposed: moduleExposed, exposesAll: moduleExposesAll, decls: decls)
    }

    // MARK: - top-level declarations

    /// A code line that starts in column 0 and is not a keyword line begins a new
    /// top-level declaration.  The block runs until the next such line.
    static func startsTopLevelDecl(_ raw: String, kind: LineKind) -> Bool {
        guard kind == .code, let f = raw.first, !f.isWhitespace else { return false }
        let t = raw.trimmingCharacters(in: .whitespaces)
        for kw in ["module ", "port module ", "import ", "type ", "type alias ", "infix ", "}", ")", "]", "-}"] {
            if t.hasPrefix(kw) { return false }
        }
        guard let c = t.first, c.isLetter || c == "(" else { return false }
        return true
    }

    /// Split an annotation on top-level `->` and return the final component (the result type).
    static func resultType(of annotation: String) -> String {
        var depth = 0
        var parts: [String] = []
        var cur = ""
        let it = Array(annotation)
        var i = 0
        while i < it.count {
            let ch = it[i]
            if ch == "(" || ch == "{" || ch == "[" { depth += 1 }
            if ch == ")" || ch == "}" || ch == "]" { depth -= 1 }
            if depth == 0 && ch == "-" && i + 1 < it.count && it[i + 1] == ">" {
                parts.append(cur); cur = ""; i += 2; continue
            }
            cur.append(ch)
            i += 1
        }
        parts.append(cur)
        return parts.last?.trimmingCharacters(in: .whitespaces) ?? annotation
    }

    static func segmentDeclarations(rawLines: [String], kinds: [LineKind], startAfter: Int,
                                    exposed: [String], exposesAll: Bool) -> [ElmDecl] {
        // collect the index of every line that opens a top-level declaration
        var starts: [Int] = []
        for i in (startAfter + 1)..<rawLines.count where startsTopLevelDecl(rawLines[i], kind: kinds[i]) {
            starts.append(i)
        }
        var out: [ElmDecl] = []
        for (k, s) in starts.enumerated() {
            let e = (k + 1 < starts.count ? starts[k + 1] : rawLines.count) - 1
            guard let nm = tokenizeWords(rawLines[s]).first else { continue }

            // The block may be `name : ann` followed by `name = body`; merge the two.
            var blockStart = s
            let blockEnd = e
            if k + 1 < starts.count,
               let nm2 = tokenizeWords(rawLines[starts[k + 1]]).first, nm2 == nm,
               rawLines[s].contains(":") && !rawLines[s].contains("=") {
                // annotation only; the body is the next block — but we emit one decl for the pair,
                // so skip emitting here and let the body block absorb the annotation instead.
                continue
            }
            if k > 0, let nmPrev = tokenizeWords(rawLines[starts[k - 1]]).first, nmPrev == nm,
               rawLines[starts[k - 1]].contains(":") && !rawLines[starts[k - 1]].contains("=") {
                blockStart = starts[k - 1]
            }

            // annotation text: everything after the first `:` on the annotation line, plus
            // any indented continuation lines before the definition line.
            var annotation: String? = nil
            if let colon = rawLines[blockStart].range(of: ":"),
               !rawLines[blockStart].contains("=") || rawLines[blockStart].distance(from: rawLines[blockStart].startIndex, to: colon.lowerBound) < (rawLines[blockStart].range(of: "=").map { rawLines[blockStart].distance(from: rawLines[blockStart].startIndex, to: $0.lowerBound) } ?? Int.max) {
                var ann = String(rawLines[blockStart][colon.upperBound...])
                var j = blockStart + 1
                while j <= blockEnd, kinds[j] == .code,
                      let f = rawLines[j].first, f.isWhitespace,
                      !rawLines[j].contains("=") {
                    ann += " " + rawLines[j].trimmingCharacters(in: .whitespaces)
                    j += 1
                }
                annotation = ann.trimmingCharacters(in: .whitespaces)
            }

            var loc = 0
            for j in blockStart...max(blockStart, blockEnd) where j < kinds.count && kinds[j] == .code { loc += 1 }

            let ret = annotation.map { resultType(of: $0) } ?? ""
            let renders = ret.contains("Html") || ret.contains("Document")

            out.append(ElmDecl(name: nm, annotation: annotation,
                               startLine: blockStart + 1, endLine: blockEnd + 1,
                               codeLines: loc,
                               isExposed: exposesAll || exposed.contains(nm),
                               rendersHtml: renders))
        }
        return out
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
