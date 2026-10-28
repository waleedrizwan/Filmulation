// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Filmulation",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Filmulation", targets: ["Filmulation"])],
    dependencies: [.package(path: "../core")],
    targets: [
        .executableTarget(name: "Filmulation", dependencies: [.product(name: "FilmulationCore", package: "core")]),
    ]
)
