#!/usr/bin/env bash
#
# Build a self-contained AppImage of Uncensored Local AI for Linux x64.
#
#   ./packaging/linux/build-appimage.sh
#
# Output: dist/UncensoredLocalAI-<version>-x86_64.AppImage
#
# Requires: flutter, and the Linux desktop toolchain listed in
# packaging/linux/README.md. appimagetool is downloaded on first run.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

APP_NAME="UncensoredLocalAI"
BINARY="portable_ai_flutter"
BUILD_DIR="build/linux/x64/release/bundle"
APPDIR="build/appimage/${APP_NAME}.AppDir"
DIST_DIR="dist"
TOOLS_DIR="build/appimage/tools"

log() { printf '\033[1;34m==>\033[0m %s\n' "$1"; }
die() { printf '\033[1;31mError:\033[0m %s\n' "$1" >&2; exit 1; }

command -v flutter >/dev/null || die "flutter is not on PATH."

VERSION="$(grep -m1 '^version:' pubspec.yaml | sed 's/version:[[:space:]]*//' | cut -d'+' -f1)"
[ -n "$VERSION" ] || die "Could not read version from pubspec.yaml."
log "Packaging ${APP_NAME} ${VERSION}"

# ── 1. Build ────────────────────────────────────────────────────────────
log "Building release bundle"
flutter build linux --release
[ -x "${BUILD_DIR}/${BINARY}" ] || die "Expected ${BUILD_DIR}/${BINARY} after build."

# ── 2. Lay out the AppDir ───────────────────────────────────────────────
log "Assembling AppDir"
rm -rf "$APPDIR"
mkdir -p "${APPDIR}/usr/bin" "${APPDIR}/usr/lib" \
         "${APPDIR}/usr/share/applications" \
         "${APPDIR}/usr/share/icons/hicolor/256x256/apps"

cp -r "${BUILD_DIR}/." "${APPDIR}/usr/bin/"

# Flutter's bundled .so files sit next to the binary; AppImage expects them
# discoverable via the AppDir library path too.
if [ -d "${BUILD_DIR}/lib" ]; then
  cp -r "${BUILD_DIR}/lib/." "${APPDIR}/usr/lib/"
fi

# ── 3. Icon ─────────────────────────────────────────────────────────────
ICON_SRC=""
for candidate in \
  "assets/icon.png" \
  "assets/logo.png" \
  "android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png" \
  "android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png"; do
  if [ -f "$candidate" ]; then ICON_SRC="$candidate"; break; fi
done

if [ -n "$ICON_SRC" ]; then
  log "Using icon ${ICON_SRC}"
  cp "$ICON_SRC" "${APPDIR}/usr/share/icons/hicolor/256x256/apps/${APP_NAME}.png"
else
  log "No icon found — generating a placeholder"
  # A 1x1 transparent PNG keeps appimagetool happy when no artwork exists.
  printf '\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89\x00\x00\x00\nIDATx\x9cc\x00\x01\x00\x00\x05\x00\x01\r\n-\xb4\x00\x00\x00\x00IEND\xaeB`\x82' \
    > "${APPDIR}/usr/share/icons/hicolor/256x256/apps/${APP_NAME}.png"
fi
cp "${APPDIR}/usr/share/icons/hicolor/256x256/apps/${APP_NAME}.png" \
   "${APPDIR}/${APP_NAME}.png"

# ── 4. Desktop entry ────────────────────────────────────────────────────
cat > "${APPDIR}/usr/share/applications/${APP_NAME}.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Uncensored Local AI
GenericName=Local AI Chat
Comment=Run uncensored local LLMs entirely on your own machine
Exec=${BINARY}
Icon=${APP_NAME}
Categories=Utility;Development;Science;
Terminal=false
StartupWMClass=portable_ai_flutter
Keywords=AI;LLM;GGUF;llama;chat;offline;
DESKTOP
cp "${APPDIR}/usr/share/applications/${APP_NAME}.desktop" "${APPDIR}/${APP_NAME}.desktop"

# ── 5. AppRun ───────────────────────────────────────────────────────────
cat > "${APPDIR}/AppRun" <<'APPRUN'
#!/usr/bin/env bash
HERE="$(dirname "$(readlink -f "${0}")")"
export LD_LIBRARY_PATH="${HERE}/usr/lib:${HERE}/usr/bin/lib:${LD_LIBRARY_PATH:-}"
# Models and chat history live outside the read-only image.
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
exec "${HERE}/usr/bin/portable_ai_flutter" "$@"
APPRUN
chmod +x "${APPDIR}/AppRun"

# ── 6. appimagetool ─────────────────────────────────────────────────────
mkdir -p "$TOOLS_DIR"
APPIMAGETOOL="${TOOLS_DIR}/appimagetool-x86_64.AppImage"
if [ ! -x "$APPIMAGETOOL" ]; then
  log "Downloading appimagetool"
  curl -fsSL -o "$APPIMAGETOOL" \
    "https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage" \
    || die "Could not download appimagetool. Download it manually to ${APPIMAGETOOL}."
  chmod +x "$APPIMAGETOOL"
fi

# ── 7. Build the image ──────────────────────────────────────────────────
mkdir -p "$DIST_DIR"
OUTPUT="${DIST_DIR}/${APP_NAME}-${VERSION}-x86_64.AppImage"
log "Building ${OUTPUT}"

# FUSE is often unavailable in containers and CI; --appimage-extract-and-run
# lets appimagetool run without it.
ARCH=x86_64 "$APPIMAGETOOL" --appimage-extract-and-run "$APPDIR" "$OUTPUT" \
  || ARCH=x86_64 "$APPIMAGETOOL" "$APPDIR" "$OUTPUT"

chmod +x "$OUTPUT"
log "Done: ${OUTPUT} ($(du -h "$OUTPUT" | cut -f1))"
echo
echo "Run it with:  ${OUTPUT}"
