#!/usr/bin/env bash
#
# Build, sign, notarize and staple Uncensored Local AI for macOS.
#
#   ./packaging/macos/build-and-notarize.sh              # build + zip only
#   ./packaging/macos/build-and-notarize.sh --sign       # + codesign
#   ./packaging/macos/build-and-notarize.sh --notarize   # + sign, notarize, staple
#
# Output: dist/UncensoredLocalAI-<version>-macos.zip  (and .dmg with --dmg)
#
# Signing needs a "Developer ID Application" certificate in your keychain.
# Notarization additionally needs a notarytool keychain profile:
#
#   xcrun notarytool store-credentials "ula-notary" \
#     --apple-id "you@example.com" \
#     --team-id "ABCDE12345" \
#     --password "app-specific-password"
#
# Override the defaults with these environment variables:
#   SIGN_IDENTITY     e.g. "Developer ID Application: Your Name (ABCDE12345)"
#   NOTARY_PROFILE    notarytool keychain profile name (default: ula-notary)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

APP_NAME="UncensoredLocalAI"
BUILD_DIR="build/macos/Build/Products/Release"
DIST_DIR="dist"
ENTITLEMENTS="macos/Runner/Release.entitlements"

DO_SIGN=false
DO_NOTARIZE=false
DO_DMG=false

for arg in "$@"; do
  case "$arg" in
    --sign)     DO_SIGN=true ;;
    --notarize) DO_SIGN=true; DO_NOTARIZE=true ;;
    --dmg)      DO_DMG=true ;;
    -h|--help)  sed -n '2,25p' "$0"; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

log()  { printf '\033[1;34m==>\033[0m %s\n' "$1"; }
warn() { printf '\033[1;33mWarning:\033[0m %s\n' "$1"; }
die()  { printf '\033[1;31mError:\033[0m %s\n' "$1" >&2; exit 1; }

[ "$(uname)" = "Darwin" ] || die "This script must run on macOS."
command -v flutter >/dev/null || die "flutter is not on PATH."

VERSION="$(grep -m1 '^version:' pubspec.yaml | sed 's/version:[[:space:]]*//' | cut -d'+' -f1)"
[ -n "$VERSION" ] || die "Could not read version from pubspec.yaml."
log "Packaging ${APP_NAME} ${VERSION}"

# ── 1. Build ────────────────────────────────────────────────────────────
log "Building release bundle"
flutter build macos --release

APP_PATH="$(find "$BUILD_DIR" -maxdepth 1 -name '*.app' -print -quit)"
[ -n "$APP_PATH" ] || die "No .app found in ${BUILD_DIR}."
log "Built ${APP_PATH}"

mkdir -p "$DIST_DIR"

# ── 2. Sign ─────────────────────────────────────────────────────────────
if [ "$DO_SIGN" = true ]; then
  IDENTITY="${SIGN_IDENTITY:-}"
  if [ -z "$IDENTITY" ]; then
    IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
      | grep 'Developer ID Application' | head -1 \
      | sed -n 's/.*"\(.*\)".*/\1/p')"
  fi
  [ -n "$IDENTITY" ] || die "No 'Developer ID Application' identity found. Set SIGN_IDENTITY."

  log "Signing as: ${IDENTITY}"

  # The app bundles llama.cpp .dylibs; each nested binary must be signed
  # before the outer bundle, innermost first.
  find "$APP_PATH" \( -name '*.dylib' -o -name '*.so' -o -name '*.framework' \) -print0 \
    | while IFS= read -r -d '' nested; do
        codesign --force --timestamp --options runtime \
          --sign "$IDENTITY" "$nested" 2>/dev/null || true
      done

  codesign --force --deep --timestamp --options runtime \
    --entitlements "$ENTITLEMENTS" \
    --sign "$IDENTITY" "$APP_PATH"

  log "Verifying signature"
  codesign --verify --deep --strict --verbose=2 "$APP_PATH"
fi

# ── 3. Zip ──────────────────────────────────────────────────────────────
ZIP_PATH="${DIST_DIR}/${APP_NAME}-${VERSION}-macos.zip"
log "Creating ${ZIP_PATH}"
rm -f "$ZIP_PATH"
# ditto preserves the bundle structure and extended attributes that
# notarization requires; `zip` does not.
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

# ── 4. Notarize ─────────────────────────────────────────────────────────
if [ "$DO_NOTARIZE" = true ]; then
  PROFILE="${NOTARY_PROFILE:-ula-notary}"
  log "Submitting to Apple for notarization (profile: ${PROFILE})"
  log "This usually takes a few minutes."

  xcrun notarytool submit "$ZIP_PATH" \
    --keychain-profile "$PROFILE" \
    --wait \
    || die "Notarization failed. Inspect the log with: xcrun notarytool log <submission-id> --keychain-profile ${PROFILE}"

  log "Stapling the ticket to the app"
  xcrun stapler staple "$APP_PATH"
  xcrun stapler validate "$APP_PATH"

  # Re-zip so the distributed archive contains the stapled bundle.
  rm -f "$ZIP_PATH"
  ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

  log "Gatekeeper assessment"
  spctl --assess --type execute --verbose=2 "$APP_PATH"
fi

# ── 5. Optional DMG ─────────────────────────────────────────────────────
if [ "$DO_DMG" = true ]; then
  DMG_PATH="${DIST_DIR}/${APP_NAME}-${VERSION}-macos.dmg"
  log "Creating ${DMG_PATH}"
  rm -f "$DMG_PATH"
  STAGING="$(mktemp -d)"
  cp -R "$APP_PATH" "$STAGING/"
  ln -s /Applications "$STAGING/Applications"
  hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" \
    -ov -format UDZO "$DMG_PATH"
  rm -rf "$STAGING"

  if [ "$DO_SIGN" = true ] && [ -n "${IDENTITY:-}" ]; then
    codesign --force --timestamp --sign "$IDENTITY" "$DMG_PATH"
  fi
fi

log "Done"
ls -lh "$DIST_DIR"

if [ "$DO_NOTARIZE" != true ]; then
  echo
  warn "This build is not notarized. Users will see 'cannot be opened because"
  warn "the developer cannot be verified' and must right-click > Open, or run:"
  warn "  xattr -dr com.apple.quarantine /Applications/$(basename "$APP_PATH")"
fi
