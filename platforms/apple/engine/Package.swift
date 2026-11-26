// swift-tools-version:5.9
import PackageDescription

// TiqianEngine: the Swift engine that boring generates from engine-haxe/src (bundle swift-f32 in
// boring.json). Sources/TiqianEngine is a checked-in symlink to the gitignored generation output
// engine-haxe/out/swift-f32/gen; produce it before building:
//
//     nix develop -c boring gen swift-f32 --project boring.json
//
// The bundle sets package-shell=none, so boring writes sources only and this manifest owns the
// package shape. `sources` lists the library roots explicitly: the generated tree may also carry
// test-harness files, which are not part of the library.
let package = Package(
    name: "TiqianEngine",
    platforms: [.macOS(.v14), .iOS(.v15)],
    products: [
        .library(name: "TiqianEngine", targets: ["TiqianEngine"]),
    ],
    targets: [
        .target(
            name: "TiqianEngine",
            sources: ["Runtime.swift", "org", "std"],
        ),
    ],
)
