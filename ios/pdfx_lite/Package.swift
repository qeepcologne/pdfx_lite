// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "pdfx_lite",
    platforms: [
        .iOS(.v13),
    ],
    products: [
        .library(name: "pdfx-lite", targets: ["pdfx_lite"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "pdfx_lite",
            dependencies: [],
            path: "Sources/pdfx_lite"
        ),
    ]
)
