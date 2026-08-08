// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "code_forge",
    platforms: [
        .macOS("10.11")
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    products: [
        .library(name: "code-forge", targets: ["code_forge"]),
    ],
    targets: [
        .target(
            name: "code_forge",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ],
            path: "Sources/code_forge"
        )
    ]
)