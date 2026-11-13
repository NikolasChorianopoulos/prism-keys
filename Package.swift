// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "RazerChromaCLI",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "chroma", targets: ["chroma"]),
    ],
    targets: [
        .target(
            name: "CRazerUSB",
            linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreFoundation")]
        ),
        .target(name: "ChromaKit", dependencies: ["CRazerUSB"],
                linkerSettings: [.linkedLibrary("sqlite3"), .linkedFramework("ApplicationServices"), .linkedFramework("AppKit")]),
        .executableTarget(name: "chroma", dependencies: ["ChromaKit", "CRazerUSB"]),
    ]
)
