// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CoreFlow",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "CoreFlow", targets: ["CoreFlow"])
    ],
    targets: [
        .target(name: "CoreFlow"),
        .testTarget(name: "CoreFlowTests", dependencies: ["CoreFlow"])
    ]
)
