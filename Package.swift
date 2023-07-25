// swift-tools-version: 5.6
// The swift-tools-version declares the minimum version of Swift required to build this package.

import Foundation
import PackageDescription

let package = Package(
    name: "TwitterImagePipeline",
    products: [
        .library(name: "TwitterImagePipeline", targets: ["TwitterImagePipeline"]),
        .library(name: "TwitterImagePipelineMP4Codec", targets: ["TwitterImagePipelineMP4Codec"]),
        .library(name: "TwitterImagePipelineWebPCodec", targets: ["TwitterImagePipelineWebPCodec"])
    ],
    targets: [
        .target(
            name: "TwitterImagePipeline",
            cSettings: [
                .define("TIP_PROJECT_VERSION", to: "2.25")
            ],
            linkerSettings: [
                .linkedFramework("UIKit", .when(platforms: [.iOS, .tvOS]))
            ]
        ),
        .target(
            name: "TIPUtils"
        ),
        .target(
            name: "TwitterImagePipelineMP4Codec",
            dependencies: [
                "TwitterImagePipeline",
                "TIPUtils"
            ]
        ),
        .binaryTarget(
            name: "WebP",
            path: "Frameworks/WebP.xcframework"
        ),
        .binaryTarget(
            name: "WebPDemux",
            path: "Frameworks/WebPDemux.xcframework"
        ),
        .target(
            name: "TwitterImagePipelineWebPCodec",
            dependencies: [
                "TwitterImagePipeline",
                "TIPUtils",
                "WebP",
                "WebPDemux"
            ],
            cSettings: [
                .define("TIPX_WEBP_ANIMATION_DECODING_ENABLED", to: "1")
            ]
        ),
        .testTarget(
            name: "TwitterImagePipelineTests",
            dependencies: [
                "TwitterImagePipeline",
                "TwitterImagePipelineMP4Codec",
                "TwitterImagePipelineWebPCodec"
            ],
            resources: [
                .process("Resources")
            ],
            cSettings: [
                .headerSearchPath("../../Sources/TwitterImagePipeline"),
                .headerSearchPath("../../Sources/TwitterImagePipelineMP4Codec"),
                .headerSearchPath("../../Sources/TwitterImagePipelineWebPCodec"),
                .headerSearchPath("../../Sources/TIPUtils"),
            ]
        )
    ]
)
