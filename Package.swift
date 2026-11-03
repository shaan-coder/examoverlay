// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ExamOverlay",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ExamOverlay",
            path: "Sources/ExamOverlay",
            exclude: ["defaults.json"],
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("ApplicationServices")
            ]
        )
    ]
)
