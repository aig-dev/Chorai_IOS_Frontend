// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CoreFlow",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "CoreFlow", targets: ["CoreFlow"])
    ],
    targets: [
        .target(name: "CoreFlow"),
        .testTarget(
            name: "CoreFlowTests",
            dependencies: ["CoreFlow"]
        )
    ],
    swiftLanguageModes: [.v6]
)
