#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

APP_NAME="${APP_NAME:-mach}"
CONFIGURATION="${CONFIGURATION:-release}"
APP_BUNDLE_PATH="${APP_BUNDLE_PATH:-${APP_NAME}.app}"
BINARY_PATH=".build/${CONFIGURATION}/${APP_NAME}"

echo "Building ${APP_NAME} (${CONFIGURATION})..."
swift build -c "${CONFIGURATION}"

echo "Creating app bundle at ${APP_BUNDLE_PATH}..."
rm -rf "${APP_BUNDLE_PATH}"
mkdir -p "${APP_BUNDLE_PATH}/Contents/MacOS"
mkdir -p "${APP_BUNDLE_PATH}/Contents/Resources"

cp "${BINARY_PATH}" "${APP_BUNDLE_PATH}/Contents/MacOS/${APP_NAME}"
cp "Resources/Info.plist" "${APP_BUNDLE_PATH}/Contents/Info.plist"
cp -R "assets" "${APP_BUNDLE_PATH}/Contents/Resources/"

# Copy additional bundle resources (icons, assets, etc.), excluding Info.plist.
while IFS= read -r -d '' resourcePath; do
    cp -R "${resourcePath}" "${APP_BUNDLE_PATH}/Contents/Resources/"
done < <(find "Resources" -mindepth 1 -maxdepth 1 ! -name "Info.plist" -print0)

chmod +x "${APP_BUNDLE_PATH}/Contents/MacOS/${APP_NAME}"

echo "Done! Run with: open ${APP_BUNDLE_PATH}"
