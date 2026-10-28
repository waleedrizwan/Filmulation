// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "FilmulationCore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "FilmulationCore", targets: ["FilmulationCore"]),
        .executable(name: "filmulate-cli", targets: ["filmulate-cli"]),
    ],
    targets: [
        .target(
            name: "FilmulationCore",
            resources: [.copy("Resources/LUTs")],
            swiftSettings: [.unsafeFlags(["-Ounchecked"])]
        ),
        .executableTarget(name: "filmulate-cli", dependencies: ["FilmulationCore"]),
        .testTarget(name: "FilmulationCoreTests", dependencies: ["FilmulationCore"]),
    ]
)
