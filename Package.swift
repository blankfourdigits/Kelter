// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Kelter",
    platforms: [
        .macOS("15.0"),
    ],
    products: [
        .executable(name: "Kelter", targets: ["KelterApp"]),
    ],
    targets: [
        // Paths, configuration, bottle management, logging. Foundation only.
        .target(name: "KelterCore"),
        // Everything that downloads, installs or launches Wine.
        .target(name: "KelterWine", dependencies: ["KelterCore"]),
        // Installing, starting and stopping the Windows Steam client.
        .target(name: "KelterSteam", dependencies: ["KelterCore", "KelterWine"]),
        // SwiftUI front end.
        .executableTarget(name: "KelterApp", dependencies: ["KelterCore", "KelterWine", "KelterSteam"]),
        .testTarget(name: "KelterCoreTests", dependencies: ["KelterCore"]),
        .testTarget(name: "KelterWineTests", dependencies: ["KelterCore", "KelterWine"]),
        .testTarget(name: "KelterSteamTests", dependencies: ["KelterCore", "KelterWine", "KelterSteam"]),
    ]
)
