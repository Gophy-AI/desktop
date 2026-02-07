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
        // Local copy with Swift 6 fix (removed `consuming` keyword in LoRAContainer.swift)
        .package(path: "vendor/mlx-swift-lm"),
        .package(url: "https://github.com/argmaxinc/WhisperKit", from: "0.9.0"),
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0"),
        .package(url: "https://github.com/google/GTMAppAuth", from: "5.0.0"),
        .package(url: "https://github.com/openid/AppAuth-iOS.git", from: "2.0.0"),
        .package(url: "https://github.com/MacPaw/OpenAI", from: "0.4.0"),
        .package(url: "https://github.com/jamesrochabrun/SwiftAnthropic", from: "1.0.0")
    ],
    targets: [
        .target(
            name: "CSQLiteVec",
            path: "Sources/CSQLiteVec",
            publicHeadersPath: "include",
            cSettings: [
                .define("SQLITE_CORE"),
                .define("SQLITE_VEC_STATIC")
            ]
        ),
        .executableTarget(
            name: "Gophy",
            dependencies: [
                "CSQLiteVec",
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXVLM", package: "mlx-swift-lm"),
                .product(name: "MLXEmbedders", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "WhisperKit", package: "WhisperKit"),
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "GTMAppAuth", package: "GTMAppAuth"),
                .product(name: "AppAuth", package: "AppAuth-iOS"),
                .product(name: "OpenAI", package: "OpenAI"),
                .product(name: "SwiftAnthropic", package: "SwiftAnthropic")
            ],
            exclude: [
                "Gophy.entitlements",
                "Info.plist"
            ]
        ),
        .testTarget(
            name: "GophyTests",
            dependencies: ["Gophy"]
        )
    ]
)
