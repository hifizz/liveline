// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LivelineCanvas",
    platforms: [
        .iOS(.v15),
        .macCatalyst(.v15)
    ],
    products: [
        .library(
            name: "LivelineCanvas",
            targets: ["LivelineCanvas"]
        )
    ],
    targets: [
        .target(
            name: "LivelineCanvas",
            path: "Sources/LivelineCanvas"
        ),
        .testTarget(
            name: "LivelineCanvasTests",
            dependencies: ["LivelineCanvas"],
            path: "Tests/LivelineCanvasTests"
        )
    ]
)
