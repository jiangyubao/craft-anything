#!/usr/bin/env bash
# Build a local "Craft Anything.app" you can drag into /Applications.
#
#   ./build_macos.sh [--skip-build]
#
# Unlike packaging/macos/package.sh (a release: universal binaries, DMG, notarization), this
# builds only the host architecture and assembles an ad-hoc-signed .app into dist/. It reuses the
# release's Info.plist template, icon, entitlements and font-licence copying, so the app behaves
# the same as a shipped one. No Apple account or signing identity is needed.
set -euo pipefail
# shellcheck source=packaging/env.sh
. "$(dirname "${BASH_SOURCE[0]}")/packaging/env.sh"

SKIP_BUILD=0
case "${1:-}" in
  "") ;;
  --skip-build) SKIP_BUILD=1 ;;
  -h | --help) sed -n '2,10p' "$0"; exit 0 ;;
  *) echo "unknown argument: $1" >&2; exit 2 ;;
esac

HERE="$ROOT/packaging/macos"
OUT_DIR="${LOCAL_APP_DIR:-$ROOT/dist}"
APP="$OUT_DIR/Craft Anything.app"
SHORT_VERSION="${VERSION%%-*}"
# Keep in sync with LSMinimumSystemVersion in Info.plist.in.
export MACOSX_DEPLOYMENT_TARGET=11.0

echo "==> Craft Anything $VERSION for macOS ($(uname -m)) -> $APP"

# ---- build (host architecture only) -------------------------------------------------------------
if [[ "$SKIP_BUILD" = 0 ]]; then
  (cd "$ROOT" && cargo build --release --locked "${CARGO_PKGS[@]}")
fi

# ---- assemble ----------------------------------------------------------------------------------
echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Licenses"
cp "$CARGO_TARGET_DIR/release/craft-anything" "$APP/Contents/MacOS/craft-anything"
# The app starts the CLI as the MCP server its coding agents use and finds it next to its own
# executable (`self_cli_path`); without it every Claude Code build fails (#91).
if [[ "$HAS_CLI" = 1 ]]; then
  cp "$CARGO_TARGET_DIR/release/craft-anything-cli" "$APP/Contents/MacOS/craft-anything-cli"
fi
cp "$ROOT/assets/app-icon/craft-anything.icns" "$APP/Contents/Resources/craft-anything.icns"
copy_font_licences "$APP/Contents/Resources/Licenses"

sed -e "s/@VERSION@/$VERSION/g" -e "s/@SHORT_VERSION@/$SHORT_VERSION/g" \
  -e "s/@BUILD_SHA@/${CRAFT_ANYTHING_BUILD_SHA:-unknown}/g" \
  "$HERE/Info.plist.in" >"$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" >/dev/null
printf 'APPL????' >"$APP/Contents/PkgInfo"

# ---- sign (ad-hoc, no identity or Apple account needed) -----------------------------------------
# Sign inside-out: nested code first, then the bundle. Ad-hoc cannot carry a secure timestamp.
echo "==> signing (ad-hoc)"
if [[ "$HAS_CLI" = 1 ]]; then
  codesign --force --sign - --options runtime --timestamp=none \
    --identifier ai.storyteller.craft-anything-cli "$APP/Contents/MacOS/craft-anything-cli"
fi
codesign --force --sign - --options runtime --timestamp=none \
  --entitlements "$HERE/entitlements.plist" "$APP/Contents/MacOS/craft-anything"
codesign --force --sign - --options runtime --timestamp=none \
  --entitlements "$HERE/entitlements.plist" "$APP"
codesign --verify --strict --deep --verbose=2 "$APP"

echo "==> done"
echo "    App:     $APP"
echo "    Install: cp -R \"$APP\" /Applications/"
"$APP/Contents/MacOS/craft-anything" --version
