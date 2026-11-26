// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "RouteKit",
    platforms: [.iOS(.v27), .macOS(.v27)],
    products: [.library(name: "RouteKit", targets: ["RouteKit"])],
    targets: [
        .target(name: "RouteKit"),
        .testTarget(name: "RouteKitTests", dependencies: ["RouteKit"]),
    ]
)
