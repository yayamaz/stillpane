// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "stillpane",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "stillpane", targets: ["Stillpane"])
    ],
    targets: [
        .target(name: "StillpaneCore"),
        .executableTarget(
            name: "Stillpane",
            dependencies: ["StillpaneCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
            ]
        ),
        .testTarget(
            name: "StillpaneCoreTests",
            dependencies: ["StillpaneCore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
