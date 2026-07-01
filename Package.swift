// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AirDictate",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "AirDictate",
            path: "Sources/AirDictate"
        )
    ]
)
