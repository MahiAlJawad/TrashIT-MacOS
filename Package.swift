// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TrashIT",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "TrashIT", targets: ["TrashIT"])
    ],
    targets: [
        .executableTarget(
            name: "TrashIT",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "TrashITTests",
            dependencies: ["TrashIT"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
