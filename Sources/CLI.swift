// CLI.swift — argument parsing and source resolution.

import Foundation

struct Options {
    var source = "."
    var outDir = "./out"
    var granularity: Granularity = .view
    var sharedPolicy: SharedPolicy = .duplicate
    var dropUnusedImports = false
    var uniform = false
    var rootHint: String? = nil
    var restarts = 250
    var paperMM = 150.0
    var keepClone = false
    var quiet = false
    var compact = false
    var cornerFlaps = false
    var cornerFlapLength: Double? = nil
}

enum CLI {

    static let usage = """
    origami — derive an origami crease pattern from the structure of an Elm codebase

    USAGE
      origami <source> [options]

      <source>   a local directory, or a git URL, or "owner/repo" on GitHub.
                 Every *.elm file underneath is analysed.

    OPTIONS
      -o, --out DIR           output directory (default ./out)
      --granularity view|module
                              view   : each rendering declaration is a flap (default)
                              module : each module is a flap
      --shared duplicate|hinge
                              how to break a module imported by several parents
                              (default duplicate)
      --drop-unused-imports   ignore imports with no reference in the body
      --uniform               give every tree edge length 1 instead of using code size
      --root MODULE           force the entry module (default: Main, else inferred)
      --restarts N            packing solver restarts (default 250)
      --paper MM              paper side length used for the centimetre columns (default 150)
      --compact               after maximising the scale, pull slack pairs together to make the
                              packing more rigid (experimental: it does not currently increase
                              the number of binding constraints)
      --corner-flaps          add four extra flaps pinned to the paper corners, so that no
                              corner region is left without a flap to absorb it (this is a
                              design decision: it changes the tree and lowers the scale)
      --corner-flap-length L  tree-edge length of those flaps (default: the shortest existing
                              leaf edge)
      --keep-clone            do not delete a repository cloned into a temp directory
      -h, --help              this text
    """

    static func parse(_ argv: [String]) -> Options? {
        var o = Options()
        var i = 1
        var sawSource = false
        while i < argv.count {
            let a = argv[i]
            func next() -> String? { i += 1; return i < argv.count ? argv[i] : nil }
            switch a {
            case "-h", "--help": return nil
            case "-o", "--out": o.outDir = next() ?? o.outDir
            case "--granularity": o.granularity = Granularity(rawValue: next() ?? "") ?? .view
            case "--shared": o.sharedPolicy = SharedPolicy(rawValue: next() ?? "") ?? .duplicate
            case "--drop-unused-imports": o.dropUnusedImports = true
            case "--uniform": o.uniform = true
            case "--root": o.rootHint = next()
            case "--restarts": o.restarts = Int(next() ?? "") ?? o.restarts
            case "--paper": o.paperMM = Double(next() ?? "") ?? o.paperMM
            case "--compact": o.compact = true
            case "--corner-flaps": o.cornerFlaps = true
            case "--corner-flap-length": o.cornerFlapLength = Double(next() ?? ""); o.cornerFlaps = true
            case "--keep-clone": o.keepClone = true
            case "-q", "--quiet": o.quiet = true
            default:
                if a.hasPrefix("-") { FileHandle.standardError.write("unknown option \(a)\n".data(using: .utf8)!); return nil }
                o.source = a; sawSource = true
            }
            i += 1
        }
        return sawSource || o.source != "." ? o : o
    }

    /// Resolve the source to a local directory, cloning if necessary.
    /// Returns (directory, temporaryCloneToDelete?).
    static func resolveSource(_ src: String) -> (dir: String, temp: String?)? {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: src, isDirectory: &isDir), isDir.boolValue {
            return (src, nil)
        }
        var url = src
        if !src.contains("://") && !src.hasPrefix("git@") {
            // treat "owner/repo" as GitHub
            let parts = src.split(separator: "/")
            guard parts.count == 2 else { return nil }
            url = "https://github.com/\(src)"
        }
        let tmp = NSTemporaryDirectory() + "origami-clone-" + UUID().uuidString
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["git", "clone", "--depth", "1", "--quiet", url, tmp]
        p.environment = ProcessInfo.processInfo.environment.merging(["GIT_LFS_SKIP_SMUDGE": "1"]) { _, b in b }
        do { try p.run() } catch { return nil }
        p.waitUntilExit()
        if p.terminationStatus != 0 { return nil }
        return (tmp, tmp)
    }

    static func findElmFiles(_ root: String) -> [String] {
        var files: [String] = []
        if let en = FileManager.default.enumerator(atPath: root) {
            for case let f as String in en where f.hasSuffix(".elm") {
                if f.contains("elm-stuff/") || f.contains("/tests/") || f.hasPrefix("tests/") { continue }
                files.append(f)
            }
        }
        return files.sorted()
    }
}
