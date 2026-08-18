// swift-tools-version: 5.10
// SPDX-License-Identifier: GPL-3.0-or-later

import PackageDescription

let package = Package(
    name: "TrashIT",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "TrashITCore", targets: ["TrashITCore"]),
        .executable(name: "TrashITDirect", targets: ["TrashITDirect"]),
        .executable(name: "trashit", targets: ["trashit"])
    ],
    targets: [
        .target(
            name: "TrashITCore",
            path: "Sources/TrashIT",
            exclude: ["App/TrashITApp.swift"],
            sources: ["App/AppModel.swift", "CLI", "Cleanup", "Models", "Persistence", "Scanning", "UI", "Utilities"],
            swiftSettings: [.define("TRASHIT_CORE")]
        ),
        .executableTarget(
            name: "TrashITDirect",
            dependencies: ["TrashITCore"],
            path: "Sources/TrashIT",
            exclude: ["App/AppModel.swift", "CLI", "Cleanup", "Models", "Persistence", "Scanning", "UI", "Utilities"],
            sources: ["App/TrashITApp.swift"],
            swiftSettings: [.define("TRASHIT_DIRECT")]
        ),
        .executableTarget(
            name: "trashit",
            dependencies: ["TrashITCore"],
            path: "Sources/TrashITCLI"
        ),
        .testTarget(
            name: "TrashITTests",
            dependencies: ["TrashITCore"]
        )
    ],
    swiftLanguageVersions: [.v5]
)
