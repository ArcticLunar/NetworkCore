// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "NetworkCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "NetworkCore",
            targets: ["NetworkCore"]
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/Alamofire/Alamofire.git",
            exact: "5.11.1"
        )
    ],
    targets: [
        .target(
            name: "NetworkCore",
            dependencies: [
                .product(name: "Alamofire", package: "Alamofire")
            ]
        ),
        .testTarget(
            name: "NetworkCoreTests",
            dependencies: ["NetworkCore"]
        )
    ]
)
