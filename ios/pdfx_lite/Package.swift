// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "pdfx_lite",
    platforms: [
        .iOS(.v15),
    ],
    products: [
        .library(name: "pdfx-lite", targets: ["pdfx_lite"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "pdfx_lite",
            dependencies: [],
            path: "Sources/pdfx_lite",
            swiftSettings: [
                // Strict concurrency. Shared state (the document/page repositories, the texture map) is reached from
                // both the platform thread and the render queue, so it is lock-guarded rather than actor-isolated:
                // pigeon's generated `PdfxApi` is a plain protocol whose completions are not `@Sendable`, which rules
                // out making the conforming class actor-isolated.
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
