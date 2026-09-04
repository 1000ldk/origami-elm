// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "origami",
    targets: [
        // The sources sit directly under Sources/ rather than Sources/origami/,
        // so the path is given explicitly.
        .executableTarget(name: "origami", path: "Sources")
    ]
)
