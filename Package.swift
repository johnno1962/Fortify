// swift-tools-version:5.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import Foundation

let name = URL(fileURLWithPath: #file)
    .deletingLastPathComponent().lastPathComponent

let package = Package(
    name: name,
    products: [
        .library(
            name: name,
            targets: [name]),
    ],
    dependencies: [
    ],
    targets: [
        .target(
            name: name,
            dependencies: [],
            path: "Sources/")
    ]
)
