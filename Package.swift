// swift-tools-version:5.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import Foundation

let name = "Fortify"

let package = Package(
    name: name,
    products: [
        .library(
            name: name,
            targets: [name]),
    ],
    dependencies: [
        .package(url: "https://github.com/johnno1962/StringIndex",
                 .upToNextMajor(from: "2.2.4")),
        .package(name: "SwiftRegex", url: "https://github.com/johnno1962/SwiftRegex5.git",
                 .upToNextMajor(from: "6.3.0")),
        .package(url: "https://github.com/johnno1962/Popen.git",
                 .upToNextMajor(from: "2.2.2")),
        .package(url: "https://github.com/johnno1962/DLKit",
                 .upToNextMajor(from: "3.6.0")),
    ],
    targets: [
        .target(
            name: name,
            dependencies: ["StringIndex", "DLKit", "Popen",
                           .product(name: "DLKitC", package: "DLKit"),
                           "SwiftRegex"],
            path: "Sources/"),
        .testTarget(
            name: "FortifyTests",
            dependencies: ["Fortify"]),
    ]
)
