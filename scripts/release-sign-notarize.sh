#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

APP_NAME="${APP_NAME:-mach}"
APP_BUNDLE_PATH="${APP_BUNDLE_PATH:-${APP_NAME}.app}"
DIST_DIR="${DIST_DIR:-dist}"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
RUN_PREFLIGHT="${RUN_PREFLIGHT:-1}"
CREATE_DMG="${CREATE_DMG:-0}"

usage() {
    cat <<'EOF'
Usage:
  SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
  NOTARY_PROFILE="your-notary-profile" \
  scripts/release-sign-notarize.sh

Optional env vars:
  APP_NAME=mach
  APP_BUNDLE_PATH=mach.app
  DIST_DIR=dist
  RUN_PREFLIGHT=1
  CREATE_DMG=0

Before first run, configure notarytool credentials:
  xcrun notarytool store-credentials "your-notary-profile" \
    --apple-id "you@example.com" --team-id "TEAMID" --password "app-specific-password"
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

if [[ -z "${SIGN_IDENTITY}" ]]; then
    echo "ERROR: SIGN_IDENTITY is required."
    usage
    exit 1
fi

if [[ -z "${NOTARY_PROFILE}" ]]; then
    echo "ERROR: NOTARY_PROFILE is required."
    usage
    exit 1
fi

if [[ "${RUN_PREFLIGHT}" == "1" ]]; then
    echo "Running strict preflight..."
    STRICT_SIGNING_CHECK=1 \
    SIGN_IDENTITY="${SIGN_IDENTITY}" \
    NOTARY_PROFILE="${NOTARY_PROFILE}" \
    APP_BUNDLE_PATH="${APP_BUNDLE_PATH}" \
    scripts/release-preflight.sh
fi

echo "Building app bundle..."
APP_NAME="${APP_NAME}" APP_BUNDLE_PATH="${APP_BUNDLE_PATH}" scripts/build-app.sh

if [[ ! -d "${APP_BUNDLE_PATH}" ]]; then
    echo "ERROR: App bundle not found at ${APP_BUNDLE_PATH}"
    exit 1
fi

plistPath="${APP_BUNDLE_PATH}/Contents/Info.plist"
if [[ ! -f "${plistPath}" ]]; then
    echo "ERROR: Missing Info.plist in bundle: ${plistPath}"
    exit 1
fi

bundleExecutable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "${plistPath}")"
shortVersion="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${plistPath}")"
buildVersion="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${plistPath}")"

execPath="${APP_BUNDLE_PATH}/Contents/MacOS/${bundleExecutable}"
if [[ ! -f "${execPath}" ]]; then
    echo "ERROR: Executable not found at ${execPath}"
    exit 1
fi

archiveBase="${APP_NAME}-${shortVersion}+${buildVersion}"
mkdir -p "${DIST_DIR}"
rawZipPath="${DIST_DIR}/${archiveBase}.zip"
notaryLogPath="${DIST_DIR}/${archiveBase}-notary.json"
finalZipPath="${DIST_DIR}/${archiveBase}-notarized.zip"

echo "Signing app with hardened runtime..."
codesign --remove-signature "${APP_BUNDLE_PATH}" >/dev/null 2>&1 || true
codesign --force --sign "${SIGN_IDENTITY}" --timestamp --options runtime "${execPath}"
codesign --force --sign "${SIGN_IDENTITY}" --timestamp --options runtime "${APP_BUNDLE_PATH}"

echo "Verifying signature..."
codesign --verify --deep --strict --verbose=2 "${APP_BUNDLE_PATH}"

# Local Gatekeeper assessment before notarization
spctl --assess --type open --verbose=4 "${APP_BUNDLE_PATH}" || true

echo "Creating zip archive for notarization: ${rawZipPath}"
rm -f "${rawZipPath}"
ditto -c -k --sequesterRsrc --keepParent "${APP_BUNDLE_PATH}" "${rawZipPath}"

echo "Submitting for notarization..."
xcrun notarytool submit "${rawZipPath}" \
    --keychain-profile "${NOTARY_PROFILE}" \
    --wait \
    --output-format json > "${notaryLogPath}"

echo "Stapling notarization ticket to app..."
xcrun stapler staple "${APP_BUNDLE_PATH}"
xcrun stapler validate "${APP_BUNDLE_PATH}"

echo "Creating final notarized zip: ${finalZipPath}"
rm -f "${finalZipPath}"
ditto -c -k --sequesterRsrc --keepParent "${APP_BUNDLE_PATH}" "${finalZipPath}"

# Final assessment after notarization + stapling
spctl --assess --type open --verbose=4 "${APP_BUNDLE_PATH}"

if [[ "${CREATE_DMG}" == "1" ]]; then
    dmgPath="${DIST_DIR}/${archiveBase}.dmg"
    dmgNotaryLogPath="${DIST_DIR}/${archiveBase}-dmg-notary.json"

    echo "Creating DMG: ${dmgPath}"
    rm -f "${dmgPath}"
    hdiutil create -volname "${APP_NAME}" -srcfolder "${APP_BUNDLE_PATH}" -ov -format UDZO "${dmgPath}" >/dev/null

    echo "Signing DMG..."
    codesign --force --sign "${SIGN_IDENTITY}" --timestamp "${dmgPath}"

    echo "Submitting DMG for notarization..."
    xcrun notarytool submit "${dmgPath}" \
        --keychain-profile "${NOTARY_PROFILE}" \
        --wait \
        --output-format json > "${dmgNotaryLogPath}"

    echo "Stapling DMG..."
    xcrun stapler staple "${dmgPath}"
    xcrun stapler validate "${dmgPath}"
fi

echo
ls -lh "${rawZipPath}" "${finalZipPath}" 2>/dev/null || true
[[ -f "${DIST_DIR}/${archiveBase}.dmg" ]] && ls -lh "${DIST_DIR}/${archiveBase}.dmg"

echo "Release signing + notarization complete."
