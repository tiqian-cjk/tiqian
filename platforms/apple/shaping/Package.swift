// swift-tools-version:5.9
import PackageDescription

// TiqianCoreText: the Apple Core Text shaping adapter and font-metrics resolver for the generated
// Swift engine (ADR 0046, ADR 0064). It implements the engine's `TextShaper` and
// `FontMetricsResolver` protocols and shares one font / CTLine cache with the frontend renderer so
// measure and draw resolve to the same Core Text objects.
let package = Package(
    name: "TiqianCoreText",
    platforms: [.macOS(.v14), .iOS(.v15)],
    products: [
        .library(name: "TiqianCoreText", targets: ["TiqianCoreText"]),
    ],
    dependencies: [
        .package(path: "../engine"),
    ],
    targets: [
        .target(
            name: "TiqianCoreText",
            dependencies: [.product(name: "TiqianEngine", package: "engine")],
            linkerSettings: [.linkedFramework("CoreText")],
        ),
        .testTarget(
            name: "TiqianCoreTextTests",
            dependencies: ["TiqianCoreText"],
        ),
    ],
)
