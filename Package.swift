// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Gophy",
    platforms: [
        .macOS("14.4")
    ],
    products: [
        .executable(
            name: "Gophy",
            targets: ["Gophy"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", .upToNextMinor(from: "2.29.3")),
        .package(url: "https://github.com/argmaxinc/WhisperKit", from: "0.9.0"),
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0")
    ],
    targets: [
        .executableTarget(
            name: "Gophy",
            dependencies: [
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXVLM", package: "mlx-swift-lm"),
                .product(name: "MLXEmbedders", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "WhisperKit", package: "WhisperKit"),
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        ),
        .testTarget(
            name: "GophyTests",
            dependencies: ["Gophy"]
        )
    ]
)
