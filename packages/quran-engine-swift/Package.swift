// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "QuranEngine",
    products: [
        .library(name: "QuranEngine", targets: ["QuranEngine"]),
    ],
    targets: [
        .target(
            name: "QuranEngine",
            // The canonical JSON corpus is bundled as a resource so the package is self-contained when
            // added to an app (e.g. Al-Islam via SwiftPM) — no repo /data dir is needed at runtime.
            // Resources/ is GENERATED from the repo-root /data by scripts/sync-package-resources.mjs.
            resources: [.copy("Resources")]
        ),
        .testTarget(name: "QuranEngineTests", dependencies: ["QuranEngine"]),
    ]
)
