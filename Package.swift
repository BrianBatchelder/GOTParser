// swift-tools-version:3.1

import PackageDescription

let package = Package(
    name: "GotParser",
    targets: [
        Target(
            name: "GotParser",
            dependencies: ["GotParserCore"]
        ),
        Target(
            name: "GotParserCore"
        )
    ],
    dependencies: [
        .Package(
            url: "https://github.com/scinfu/SwiftSoup.git",
            majorVersion: 1
        )
    ]
)
