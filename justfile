# MoleUI Build Script (Native Xcode + Just)

default:
    @just --list

scheme := "MoleUI"
app_name := "Mole UI"

# ============================================
# Development
# ============================================

# Build Debug
build:
    xcodebuild -scheme {{scheme}} \
        -configuration Debug \
        -destination 'platform=macOS' \
        CODE_SIGN_IDENTITY="-" \
        CODE_SIGNING_REQUIRED=NO \
        build

# Build Release
build-release:
    xcodebuild -scheme {{scheme}} \
        -configuration Release \
        -archivePath build/{{app_name}}.xcarchive \
        archive

# Run
run: build
    @open ~/Library/Developer/Xcode/DerivedData/MoleUI-*/Build/Products/Debug/"{{app_name}}.app"

# Clean
clean:
    xcodebuild clean -scheme {{scheme}}
    rm -rf ~/Library/Developer/Xcode/DerivedData/MoleUI-*

# ============================================
# Code Quality
# ============================================

fmt:
    swiftformat MoleUI/

lint:
    swiftlint

# ============================================
# Mole CLI
# ============================================

# Update bundled Mole CLI
update-mole:
    brew upgrade mole || brew install mole
    rm -rf Resources/mole/*
    cp -R /opt/homebrew/Cellar/mole/*/libexec/* Resources/mole/
    cp /opt/homebrew/Cellar/mole/*/bin/mole Resources/mole/
    sed -i '' 's|SCRIPT_DIR=.*|SCRIPT_DIR="$$(cd \\"$$(dirname \\"$${BASH_SOURCE[0]}\\")\\" \&\& pwd)"|' Resources/mole/mole

# ============================================
# Release
# ============================================

# Package DMG
package: build-release
    mkdir -p dist
    create-dmg \
        --volname "{{app_name}}" \
        --window-pos 200 120 \
        --window-size 600 400 \
        --icon-size 100 \
        --icon "{{app_name}}.app" 150 185 \
        --app-drop-link 450 185 \
        dist/MoleUI.dmg \
        build/"{{app_name}}".xcarchive/Products/Applications/ || true

sign-and-notarize: package
    codesign --force --deep --timestamp --options runtime \
        --sign "Developer ID Application: Fuyao Qin (646VSJ9K5F)" \
        dist/MoleUI.dmg
    xcrun notarytool submit dist/MoleUI.dmg \
        --keychain-profile "notary-profile" \
        --wait

# ============================================
# CI/CD
# ============================================

ci-build: build
    @echo "CI build done"

ci-release: build-release package sign-and-notarize
    @echo "CI release done"

# Project info
info:
    @echo "Swift: $(swift --version | head -1)"
    @echo "Xcode: $(xcodebuild -version | head -1)"
    @Resources/mole/mole version 2>/dev/null | head -1 || echo "Mole CLI: not found"
