// swift-tools-version: 5.9

// WARNING:
// This is an Xcode App Playground package. Open the .swiftpm folder in Xcode 15 or later.
// Xcode edits the app settings below (Team, bundle ID) when you change them in its UI.

import PackageDescription
import AppleProductTypes

let package = Package(
    name: "Flame Test Trivia",
    platforms: [
        .iOS("17.0")
    ],
    products: [
        .iOSApplication(
            name: "Flame Test Trivia",
            targets: ["AppModule"],
            bundleIdentifier: "com.linearair.flametesttrivia",
            teamIdentifier: "",
            displayVersion: "1.0",
            bundleVersion: "1",
            appIcon: .placeholder(icon: .sparkle),
            accentColor: .presetColor(.orange),
            supportedDeviceFamilies: [
                .pad,
                .phone
            ],
            supportedInterfaceOrientations: [
                .portrait,
                .landscapeRight,
                .landscapeLeft,
                .portraitUpsideDown(.when(deviceFamilies: [.pad]))
            ]
        )
    ],
    targets: [
        .executableTarget(
            name: "AppModule",
            path: "."
        )
    ]
)
