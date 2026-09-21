// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "RouteKit",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [.library(name: "RouteKit", targets: ["RouteKit"])],
    targets: [
        .target(name: "RouteKit"),
        .testTarget(name: "RouteKitTests", dependencies: ["RouteKit"]),
    ]
)
