// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PhotoTriage",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "PhotoTriage", targets: ["PhotoTriage"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.24.0")
    ],
    targets: [
        .executableTarget(
            name: "PhotoTriage",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: "Sources/PhotoTriage",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "PhotoTriageTests",
            dependencies: ["PhotoTriage"],
            path: "Tests/PhotoTriageTests"
        )
    ]
)
