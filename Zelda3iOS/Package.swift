// swift-tools-version:5.9
import PackageDescription

// NOTE: This Package.swift is provided as a reference for dependency
// resolution only. In practice, for an iOS *app* (not a library), you'll
// want to create an actual Xcode App project and add this SDL2 package
// as a dependency via File > Add Package Dependencies, rather than trying
// to run this as a standalone SPM executable — SPM executables can't
// produce a signed .app/.ipa with Info.plist, entitlements, etc. the way
// an Xcode App target can. See README.md "Building" section.
let package = Package(
    name: "Zelda3iOS",
    platforms: [.iOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/ctreffs/SwiftSDL2.git", from: "1.4.0")
    ],
    targets: [
        .target(
            name: "CEngine",
            dependencies: [
                .product(name: "SDL", package: "SwiftSDL2")
            ],
            path: "Sources/CEngine",
            exclude: [
                // Desktop-only asset extraction tooling (Python), not part
                // of the compiled engine.
            ],
            cSettings: [
                .headerSearchPath("."),
                .headerSearchPath("src"),
                .headerSearchPath("snes"),
                .headerSearchPath("third_party"),
                .headerSearchPath("src/platform/ios"),
                .define("__IPHONEOS__"),
                .define("VAR_ARRAYS"),
            ]
        )
    ]
)
