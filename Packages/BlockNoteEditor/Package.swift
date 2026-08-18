// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BlockNoteEditor",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        .library(name: "BlockNoteEditor", targets: ["BlockNoteEditor"]),
    ],
    dependencies: [
        .package(path: "../CoreFlow"),
    ],
    targets: [
        .target(
            name: "BlockNoteEditor",
            resources: [.process("Resources")],
            linkerSettings: [.linkedFramework("WebKit")]
        ),
        .testTarget(
            name: "BlockNoteEditorTests",
            dependencies: [
                "BlockNoteEditor",
                .product(name: "CoreFlow", package: "CoreFlow"),
            ]
        ),
    ]
)
