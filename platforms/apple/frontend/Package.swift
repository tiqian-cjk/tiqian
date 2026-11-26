// swift-tools-version:5.9
import PackageDescription

// TiqianUI: the SwiftUI / AppKit / UIKit frontend for the Tiqian CJK typesetting engine, the Apple
// peer of the Compose `CjkText`. It vends content-agnostic views (`CJKText`, `CJKTextView`) with
// read-only native selection and copy. Apps (the bundled demo and downstream readers) depend on
// this package and `import TiqianUI`. Pagination is not here; that belongs to the pageflow engine.
//
// Module layering (ADR 0064):
//   TiqianEngine    ../engine   the Swift engine boring generates from engine-haxe (swift-f32)
//   TiqianCoreText  ../shaping  Core Text shaper, font metrics, shared font / line cache
//   Tiqian          this        Core Text renderer, paragraph backend, document facade
//   TiqianUI        this        views over the facade; the only product
let package = Package(
    name: "TiqianUI",
    platforms: [.macOS(.v14), .iOS(.v15)],
    products: [
        .library(name: "TiqianUI", targets: ["TiqianUI"]),
    ],
    dependencies: [
        .package(path: "../engine"),
        .package(path: "../shaping"),
    ],
    targets: [
        .target(
            name: "Tiqian",
            dependencies: [
                .product(name: "TiqianEngine", package: "engine"),
                .product(name: "TiqianCoreText", package: "shaping"),
            ],
            linkerSettings: [.linkedFramework("CoreText")],
        ),
        .target(
            name: "TiqianUI",
            dependencies: ["Tiqian"],
        ),
        .testTarget(
            name: "TiqianTests",
            dependencies: [
                "Tiqian",
                .product(name: "TiqianEngine", package: "engine"),
                .product(name: "TiqianCoreText", package: "shaping"),
            ],
        ),
        .testTarget(
            name: "TiqianUITests",
            dependencies: ["TiqianUI"],
        ),
    ],
)
