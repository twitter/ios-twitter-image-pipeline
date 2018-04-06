#!/bin/sh

set -eu

function ci_lib() {
    NAME=$1
    xcodebuild -project TwitterImagePipeline.xcodeproj \
               -scheme "TwitterImagePipeline.framework" \
               -destination "platform=iOS Simulator,name=${NAME}" \
               -sdk iphonesimulator \
               build test
}

function ci_demo() {
    NAME=$1
    xcodebuild -project TwitterImagePipeline.xcodeproj \
               -scheme "TIP Sample App" \
               -destination "platform=iOS Simulator,name=${NAME}" \
               -sdk iphonesimulator \
               build
}


ci_lib "iPhone 6" && ci_demo "iPhone 6"
ci_lib "iPhone 7" && ci_demo "iPhone 7"
