// swift-tools-version:5.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import Foundation

let name = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().lastPathComponent

let package = Package(
    name: name,
    products: [
        .library(
            name: name,
            targets: [name]),
    ],
    dependencies: [
        .package(url: "https://github.com/johnno1962/StringIndex", .upToNextMajor(from: "2.0.1")),
        .package(url: "https://github.com/johnno1962/DLKit", .upToNextMajor(from: "3.2.0")),
    ],
    targets: [
        .target(
            name: name,
            dependencies: ["StringIndex", "DLKit",
                           .product(name: "DLKitC", package: "DLKit")],
            path: "Sources/"),
        .testTarget(
            name: "FortifyTests",
            dependencies: ["Fortify"]),
    ]
)
