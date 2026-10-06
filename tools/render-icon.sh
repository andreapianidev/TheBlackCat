#!/bin/zsh
# Rebuilds the app icon from the cat rig. Run from the project root.
set -e
mkdir -p build
swiftc -O Shared/Rig/*.swift tools/IconRenderer/main.swift -o build/render-icon
build/render-icon Resources/Assets.xcassets/AppIcon.appiconset
