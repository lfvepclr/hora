#!/bin/bash
# Hora Notarization Script
# ===========================
# Submits the DMG to Apple for notarization, staples the ticket,
# and verifies the result.
#
# Usage: ./scripts/notarize.sh
#
# Prerequisites:
#   - Valid Apple Developer account
#   - App-specific password (generate at https://appleid.apple.com/account/manage)
#   - Xcode command line tools installed
#
# Set environment variables before running:
#   APPLE_ID     - Your Apple ID email
#   TEAM_ID      - Your Apple Developer Team ID
#   APP_PASSWORD - App-specific password

set -euo pipefail

# Developer credentials (override via environment variables)
APPLE_ID="${APPLE_ID:-your-apple-id@example.com}"
TEAM_ID="${TEAM_ID:-YOUR_TEAM_ID}"
APP_PASSWORD="${APP_PASSWORD:-your-app-specific-password}"

DMG_PATH="dist/Hora.dmg"

# Verify DMG exists
if [[ ! -f "$DMG_PATH" ]]; then
    echo "❌ DMG not found at: $DMG_PATH"
    echo "   Run 'swift run DMGBuilderExec' first to build the DMG."
    exit 1
fi

echo "╔══════════════════════════════════════╗"
echo "║   Hora Notarization Script         ║"
echo "╚══════════════════════════════════════╝"
echo ""

# Step 1: Submit for notarization
echo "📤 Submitting for notarization..."
echo "   File: $DMG_PATH"
echo ""

xcrun notarytool submit "$DMG_PATH" \
    --apple-id "$APPLE_ID" \
    --password "$APP_PASSWORD" \
    --team-id "$TEAM_ID" \
    --wait

if [ $? -ne 0 ]; then
    echo ""
    echo "❌ Notarization failed. Check the output above for errors."
    echo "   Tip: Run 'xcrun notarytool log <submission-id> --apple-id ...' for details."
    exit 1
fi

echo ""
echo "✅ Notarization successful!"
echo ""

# Step 2: Staple notarization ticket
echo "📎 Stapling notarization ticket..."
xcrun stapler staple "$DMG_PATH"

if [ $? -ne 0 ]; then
    echo ""
    echo "❌ Failed to staple notarization ticket."
    exit 1
fi

echo ""
echo "✅ Notarization ticket stapled successfully!"
echo ""

# Step 3: Verify
echo "✅ Verifying notarization..."
spctl --assess --type open --context context:primary-signature -vv "$DMG_PATH"

echo ""
echo "🔑 SHA256:"
shasum -a 256 "$DMG_PATH"

echo ""
echo "🎉 All done! Your DMG is now notarized and ready for distribution."
