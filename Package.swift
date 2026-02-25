// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VoiceMemoTranscriptsApp",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "VoiceMemoTranscriptsApp", targets: ["AppShell"]),
        .library(name: "Domain", targets: ["Domain"]),
        .library(name: "Data", targets: ["Data"]),
        .library(name: "Platform", targets: ["Platform"]),
        .library(name: "FeatureRecordings", targets: ["FeatureRecordings"]),
        .library(name: "FeatureTranscriptViewer", targets: ["FeatureTranscriptViewer"]),
        .library(name: "FeatureExport", targets: ["FeatureExport"])
    ],
    targets: [
        .target(name: "Domain"),
        .target(name: "Data", dependencies: ["Domain"]),
        .target(name: "Platform", dependencies: ["Domain"]),
        .target(name: "FeatureRecordings", dependencies: ["Domain"]),
        .target(name: "FeatureTranscriptViewer", dependencies: ["Domain"]),
        .target(name: "FeatureExport", dependencies: ["Domain"]),
        .executableTarget(
            name: "AppShell",
            dependencies: [
                "Domain",
                "Data",
                "Platform",
                "FeatureRecordings",
                "FeatureTranscriptViewer",
                "FeatureExport"
            ],
            resources: [
                .copy("Resources/extract-apple-voice-memos-transcript")
            ]
        )
    ]
)
