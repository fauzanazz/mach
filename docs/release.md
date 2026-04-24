# mach Release Guide

## Prerequisites

- macOS host with Xcode command line tools
- Developer ID Application certificate in your login keychain
- Notary credentials saved with `notarytool`

```bash
xcrun notarytool store-credentials "mach-notary" \
  --apple-id "you@example.com" \
  --team-id "TEAMID" \
  --password "app-specific-password"
```

## 1) Preflight checks

```bash
scripts/release-preflight.sh
```

For strict signing/notary checks:

```bash
STRICT_SIGNING_CHECK=1 \
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE="mach-notary" \
scripts/release-preflight.sh
```

## 2) Build, sign, notarize

```bash
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE="mach-notary" \
scripts/release-sign-notarize.sh
```

Optional DMG output:

```bash
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE="mach-notary" \
CREATE_DMG=1 \
scripts/release-sign-notarize.sh
```

## 3) Artifacts

Generated in `dist/`:

- `mach-<version>+<build>.zip` (submitted to notarization)
- `mach-<version>+<build>-notarized.zip` (distribute this)
- optional `mach-<version>+<build>.dmg` when `CREATE_DMG=1`

## GitHub Actions CI/CD

Workflows:

- `.github/workflows/ci.yml`
  - Runs on push / pull request / manual dispatch
  - Builds debug + release
  - Builds `mach.app`
  - Runs `scripts/release-preflight.sh`
  - Uploads unsigned CI app zip artifact

- `.github/workflows/release.yml`
  - Runs on tag push `v*` and manual dispatch
  - Validates tag version matches `CFBundleShortVersionString`
  - Imports Developer ID certificate
  - Stores notary profile
  - Runs `scripts/release-sign-notarize.sh`
  - Uploads notarized artifacts
  - Publishes GitHub release for tag builds

- `.github/workflows/version-bump.yml`
  - Manual workflow to bump `CFBundleShortVersionString` + `CFBundleVersion`
  - Can create a PR (default) or push directly
  - Optional tag creation when pushing directly

Required GitHub secrets for release workflow:

- `APPLE_SIGNING_CERT_BASE64` — base64-encoded `.p12` certificate export
- `APPLE_SIGNING_CERT_PASSWORD` — password for `.p12`
- `APPLE_KEYCHAIN_PASSWORD` — temporary keychain password for runner
- `APPLE_SIGN_IDENTITY` — exact signing identity string (e.g. `Developer ID Application: ...`)
- `APPLE_ID` — Apple ID email for notarization
- `APPLE_TEAM_ID` — Apple Developer Team ID
- `APPLE_APP_SPECIFIC_PASSWORD` — app-specific password for Apple ID

## Version bump flow (recommended)

1. Run **Version Bump** workflow with your new semver (e.g. `0.2.0`)
2. Keep `create_pull_request=true` (default)
3. Merge the generated PR after CI passes
4. Create release tag `v0.2.0` on `main`
5. Release workflow runs automatically and publishes notarized artifacts

## Branch protection

See: `docs/branch-protection.md`

## Notes

- Bundle metadata is in `Resources/Info.plist`.
- App icon source file is `Resources/mach.icns`.
- Rebuild icon (if needed):

```bash
scripts/generate-icon.sh
```
