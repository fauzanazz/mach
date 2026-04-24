#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

STRICT_SIGNING_CHECK="${STRICT_SIGNING_CHECK:-0}"
SKIP_BUILD="${SKIP_BUILD:-0}"
APP_BUNDLE_PATH="${APP_BUNDLE_PATH:-mach.app}"

FAILURES=0
WARNINGS=0

ok() {
    echo "✅ $1"
}

warn() {
    echo "⚠️  $1"
    WARNINGS=$((WARNINGS + 1))
}

fail() {
    echo "❌ $1"
    FAILURES=$((FAILURES + 1))
}

require_command() {
    local cmd="$1"
    if command -v "$cmd" >/dev/null 2>&1; then
        ok "Found command: ${cmd}"
    else
        fail "Missing command: ${cmd}"
    fi
}

plist_value() {
    local plistPath="$1"
    local key="$2"
    /usr/libexec/PlistBuddy -c "Print :${key}" "${plistPath}" 2>/dev/null || true
}

echo "Running release preflight checks..."

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    if [[ -n "$(git status --porcelain)" ]]; then
        warn "Working tree is not clean (uncommitted changes present)"
    else
        ok "Working tree is clean"
    fi
fi

auto_commands=(swift plutil codesign xcrun spctl ditto security)
for cmd in "${auto_commands[@]}"; do
    require_command "${cmd}"
done

if [[ -x "/usr/libexec/PlistBuddy" ]]; then
    ok "Found command: /usr/libexec/PlistBuddy"
else
    fail "Missing command: /usr/libexec/PlistBuddy"
fi

if [[ -f "Resources/Info.plist" ]]; then
    ok "Resources/Info.plist exists"
else
    fail "Resources/Info.plist is missing"
fi

if [[ -f "assets/manifest.json" ]]; then
    ok "assets/manifest.json exists"
else
    fail "assets/manifest.json is missing"
fi

if [[ -x "scripts/build-app.sh" ]]; then
    ok "scripts/build-app.sh is executable"
else
    fail "scripts/build-app.sh is not executable"
fi

if [[ -f "Resources/Info.plist" ]]; then
    bundleId="$(plist_value "Resources/Info.plist" "CFBundleIdentifier")"
    bundleName="$(plist_value "Resources/Info.plist" "CFBundleName")"
    bundleExec="$(plist_value "Resources/Info.plist" "CFBundleExecutable")"
    bundleVersion="$(plist_value "Resources/Info.plist" "CFBundleVersion")"
    bundleShortVersion="$(plist_value "Resources/Info.plist" "CFBundleShortVersionString")"
    bundlePackageType="$(plist_value "Resources/Info.plist" "CFBundlePackageType")"
    lsUiElement="$(plist_value "Resources/Info.plist" "LSUIElement")"
    iconFile="$(plist_value "Resources/Info.plist" "CFBundleIconFile")"

    [[ -n "${bundleId}" ]] && ok "CFBundleIdentifier=${bundleId}" || fail "CFBundleIdentifier is missing"
    [[ -n "${bundleName}" ]] && ok "CFBundleName=${bundleName}" || fail "CFBundleName is missing"
    [[ -n "${bundleExec}" ]] && ok "CFBundleExecutable=${bundleExec}" || fail "CFBundleExecutable is missing"
    [[ -n "${bundleVersion}" ]] && ok "CFBundleVersion=${bundleVersion}" || fail "CFBundleVersion is missing"
    [[ -n "${bundleShortVersion}" ]] && ok "CFBundleShortVersionString=${bundleShortVersion}" || fail "CFBundleShortVersionString is missing"

    if [[ "${bundlePackageType}" == "APPL" ]]; then
        ok "CFBundlePackageType=APPL"
    else
        fail "CFBundlePackageType should be APPL (current: ${bundlePackageType:-unset})"
    fi

    if [[ "${lsUiElement}" == "true" ]]; then
        ok "LSUIElement=true (menu bar app)"
    else
        warn "LSUIElement is not true"
    fi

    if [[ -n "${iconFile}" ]]; then
        if [[ -f "Resources/${iconFile}.icns" || -f "Resources/${iconFile}" ]]; then
            ok "Bundle icon exists for CFBundleIconFile=${iconFile}"
        else
            fail "CFBundleIconFile is set (${iconFile}) but corresponding file is missing in Resources/"
        fi
    else
        warn "CFBundleIconFile is not set"
    fi

    if [[ -n "${bundleShortVersion}" && ! "${bundleShortVersion}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        warn "CFBundleShortVersionString is not semver-like (x.y.z): ${bundleShortVersion}"
    fi
fi

if [[ "${SKIP_BUILD}" != "1" ]]; then
    echo "Building app bundle for structure checks..."
    if APP_BUNDLE_PATH="${APP_BUNDLE_PATH}" scripts/build-app.sh >/tmp/mach-preflight-build.log 2>&1; then
        ok "App bundle builds successfully"
    else
        fail "scripts/build-app.sh failed"
        tail -n 60 /tmp/mach-preflight-build.log || true
    fi
else
    warn "Skipping build check (SKIP_BUILD=1)"
fi

if [[ -d "${APP_BUNDLE_PATH}" ]]; then
    ok "${APP_BUNDLE_PATH} exists"
else
    fail "${APP_BUNDLE_PATH} does not exist"
fi

if [[ -d "${APP_BUNDLE_PATH}/Contents/MacOS" ]]; then
    ok "${APP_BUNDLE_PATH}/Contents/MacOS exists"
else
    fail "${APP_BUNDLE_PATH}/Contents/MacOS is missing"
fi

if [[ -f "${APP_BUNDLE_PATH}/Contents/Info.plist" ]]; then
    ok "${APP_BUNDLE_PATH}/Contents/Info.plist exists"
else
    fail "${APP_BUNDLE_PATH}/Contents/Info.plist is missing"
fi

if [[ -d "${APP_BUNDLE_PATH}/Contents/Resources/assets" ]]; then
    ok "Bundled assets directory exists"
else
    fail "Bundled assets directory is missing"
fi

if [[ "${STRICT_SIGNING_CHECK}" == "1" ]]; then
    if [[ -z "${SIGN_IDENTITY:-}" ]]; then
        fail "SIGN_IDENTITY is required when STRICT_SIGNING_CHECK=1"
    else
        if security find-identity -v -p codesigning 2>/dev/null | grep -Fq "${SIGN_IDENTITY}"; then
            ok "Signing identity found in keychain"
        else
            fail "Signing identity not found: ${SIGN_IDENTITY}"
        fi
    fi

    if [[ -z "${NOTARY_PROFILE:-}" ]]; then
        fail "NOTARY_PROFILE is required when STRICT_SIGNING_CHECK=1"
    else
        notaryOutput=""
        if notaryOutput="$(xcrun notarytool history --keychain-profile "${NOTARY_PROFILE}" --output-format json 2>&1)"; then
            ok "Notary profile is usable: ${NOTARY_PROFILE}"
        else
            if echo "${notaryOutput}" | grep -qi "No Keychain password item found\|Could not find\|Invalid"; then
                fail "Notary profile appears invalid or missing: ${NOTARY_PROFILE}"
            else
                warn "Could not fully verify notary profile (${NOTARY_PROFILE}); try again with network connectivity"
            fi
        fi
    fi
else
    [[ -n "${SIGN_IDENTITY:-}" ]] || warn "SIGN_IDENTITY is not set"
    [[ -n "${NOTARY_PROFILE:-}" ]] || warn "NOTARY_PROFILE is not set"
fi

echo
if [[ "${FAILURES}" -gt 0 ]]; then
    echo "Preflight FAILED with ${FAILURES} error(s) and ${WARNINGS} warning(s)."
    exit 1
fi

echo "Preflight PASSED with ${WARNINGS} warning(s)."
