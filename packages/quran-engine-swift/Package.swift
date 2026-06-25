// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "QuranEngine",
    products: [
        .library(name: "QuranEngine", targets: ["QuranEngine"]),
    ],
    targets: [
        .target(name: "QuranEngine"),
        .testTarget(name: "QuranEngineTests", dependencies: ["QuranEngine"]),
    ]
)
