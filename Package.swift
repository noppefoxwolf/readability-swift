// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ReadabilitySwift",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(
            name: "ReadabilitySwift",
            targets: ["ReadabilitySwift"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.13.6"),
    ],
    targets: [
        .target(
            name: "ReadabilitySwift",
            dependencies: [
                .product(name: "SwiftSoup", package: "SwiftSoup"),
            ]
        ),
        .testTarget(
            name: "ReadabilitySwiftTests",
            dependencies: ["ReadabilitySwift"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
