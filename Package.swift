// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "QingLi",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "QingLiCore", targets: ["QingLiCore"]),
        .executable(name: "QingLi", targets: ["QingLi"]),
        .executable(name: "QingLiWidgetExtension", targets: ["QingLiWidgetExtension"])
    ],
    dependencies: [
        .package(url: "https://github.com/wbx1-Ltd/LunarCore-Swift.git", exact: "1.2.0")
    ],
    targets: [
        .target(
            name: "QingLiCore",
            dependencies: [.product(name: "LunarCore", package: "lunarcore-swift")],
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "QingLi",
            dependencies: ["QingLiCore"],
            exclude: ["Info.plist", "QingLi.entitlements", "Assets.xcassets"]
        ),
        .executableTarget(name: "QingLiWidgetExtension", dependencies: ["QingLiCore"], exclude: ["Info.plist", "QingLiWidgetExtension.entitlements"]),
        .testTarget(name: "QingLiCoreTests", dependencies: ["QingLiCore"], exclude: ["Info.plist"])
    ]
)
