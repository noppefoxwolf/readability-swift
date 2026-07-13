// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Example",
    platforms: [
        .macOS(.v15),
    ],
    dependencies: [
        .package(path: ".."),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .executableTarget(
            name: "Example",
            dependencies: [
                .product(name: "ReadabilitySwift", package: "readability-swift"),
            ]
        ),
        .testTarget(
            name: "ExampleTests",
            dependencies: ["Example"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
