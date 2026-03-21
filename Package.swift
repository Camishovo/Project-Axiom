// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Axiom",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(name: "Axiom", targets: ["Axiom"])
    ],
    dependencies: [
        // Add dependencies as needed
        // .package(url: "https://github.com/apple/swift-markdown.git", from: "0.3.0"),
    ],
    targets: [
        .target(
            name: "Axiom",
            path: "Axiom"
        )
    ]
)
