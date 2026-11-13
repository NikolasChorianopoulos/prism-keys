// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "PrismKeys",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "PrismKeys", targets: ["PrismKeys"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .target(
            name: "CRazerUSB",
            linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreFoundation")]
        ),
        .target(
            name: "PrismCore",
            dependencies: ["CRazerUSB"],
            linkerSettings: [.linkedLibrary("sqlite3"), .linkedFramework("ApplicationServices"), .linkedFramework("AppKit")]
        ),
        .executableTarget(
            name: "PrismKeys",
            dependencies: ["PrismCore", .product(name: "Sparkle", package: "Sparkle")],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
    ]
)
