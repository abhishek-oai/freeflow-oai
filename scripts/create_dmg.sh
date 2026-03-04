#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="${APP_NAME:-FreeFlow Dev}"
BUILD_DIR="${BUILD_DIR:-${ROOT_DIR}/build}"
APP_BUNDLE="${APP_BUNDLE:-${BUILD_DIR}/${APP_NAME}.app}"
DMG_PATH="${DMG_PATH:-${BUILD_DIR}/${APP_NAME}.dmg}"
STAGING_DIR="${BUILD_DIR}/dmg-staging"
VOLUME_NAME="${VOLUME_NAME:-${APP_NAME}}"
SKIP_BUILD="${SKIP_BUILD:-0}"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"

cleanup() {
  rm -rf "${STAGING_DIR}"
}

trap cleanup EXIT

if [[ "${SKIP_BUILD}" != "1" ]]; then
  make -C "${ROOT_DIR}" all \
    CODESIGN_IDENTITY="${CODESIGN_IDENTITY}" \
    APP_NAME="${APP_NAME}" \
    BUILD_DIR="${BUILD_DIR}"
fi

if [[ ! -d "${APP_BUNDLE}" ]]; then
  echo "App bundle not found at ${APP_BUNDLE}" >&2
  exit 1
fi

mkdir -p "$(dirname "${DMG_PATH}")"
rm -f "${DMG_PATH}"
mkdir -p "${STAGING_DIR}"

cp -R "${APP_BUNDLE}" "${STAGING_DIR}/"
ln -s /Applications "${STAGING_DIR}/Applications"

hdiutil create \
  -volname "${VOLUME_NAME}" \
  -srcfolder "${STAGING_DIR}" \
  -ov \
  -format UDZO \
  "${DMG_PATH}" > /dev/null

echo "Created ${DMG_PATH}"
