#!/usr/bin/env bash
set -euo pipefail

# AutoSuggest installer — downloads latest release DMG, mounts, copies to /Applications, launches.

REPO="2002bishwajeet/autosuggest"
APP_NAME="AutoSuggest"

echo "==> Fetching latest release info..."
DOWNLOAD_URL=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
  | grep "browser_download_url.*\.dmg" \
  | head -1 \
  | cut -d '"' -f 4)

if [ -z "${DOWNLOAD_URL:-}" ]; then
  echo "Error: Could not find a .dmg asset in the latest release."
  echo "Visit https://github.com/${REPO}/releases to download manually."
  exit 1
fi

TMPDIR_PATH=$(mktemp -d)
DMG_PATH="${TMPDIR_PATH}/${APP_NAME}.dmg"
MOUNT_POINT="${TMPDIR_PATH}/mount"

cleanup() {
  hdiutil detach "${MOUNT_POINT}" -quiet 2>/dev/null || true
  rm -rf "${TMPDIR_PATH}"
}
trap cleanup EXIT

echo "==> Downloading ${APP_NAME}..."
curl -fSL --progress-bar -o "${DMG_PATH}" "${DOWNLOAD_URL}"

echo "==> Mounting disk image..."
mkdir -p "${MOUNT_POINT}"
hdiutil attach "${DMG_PATH}" -mountpoint "${MOUNT_POINT}" -nobrowse -quiet

APP_PATH=$(find "${MOUNT_POINT}" -maxdepth 1 -name "*.app" | head -1)
if [ -z "${APP_PATH:-}" ]; then
  echo "Error: No .app found in the DMG."
  exit 1
fi

DEST="/Applications/${APP_NAME}.app"
if [ -d "${DEST}" ]; then
  echo "==> Removing existing installation..."
  rm -rf "${DEST}"
fi

echo "==> Installing to /Applications..."
cp -R "${APP_PATH}" "${DEST}"

echo "==> Cleaning up..."
# cleanup runs via trap

echo ""
echo "Installed ${APP_NAME} to /Applications."
echo ""

read -rp "Launch ${APP_NAME} now? [Y/n] " response
case "${response}" in
  [nN]*)
    echo "Run it any time from /Applications or Spotlight."
    ;;
  *)
    echo "==> Launching ${APP_NAME}..."
    open "${DEST}"
    ;;
esac
