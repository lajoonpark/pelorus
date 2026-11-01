// swift-tools-version: 5.9
import PackageDescription

var products: [Product] = [
    .library(name: "RadialCore", targets: ["RadialCore"]),
]
var targets: [Target] = [
    .target(name: "RadialCore"),
    .testTarget(name: "RadialCoreTests", dependencies: ["RadialCore"]),
]

#if os(macOS)
products.append(.executable(name: "Lodestar", targets: ["Lodestar"]))
targets.append(.executableTarget(name: "Lodestar", dependencies: ["RadialCore"]))
#endif

let package = Package(
    name: "Lodestar",
    platforms: [.macOS(.v14)],
    products: products,
    targets: targets
)
