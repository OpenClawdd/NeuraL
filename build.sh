#!/bin/bash
xcodebuild -project NeuraL.xcodeproj \
  -scheme NeuraL \
  -configuration Release \
  -sdk iphoneos \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  -derivedDataPath ./DerivedData

APP=$(find ./DerivedData -name "NeuraL.app" -type d | head -1)
mkdir Payload
cp -R "$APP" Payload/
zip -r NeuraL-unsigned.ipa Payload
rm -rf Payload
