#!/bin/zsh
set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "usage: $0 <path-to-app> <output-dmg> [volume-name]" >&2
  exit 1
fi

APP_PATH="${1}"
OUTPUT_DMG="${2}"
VOLUME_NAME="${3:-SmartClose}"

if [[ ! -d "${APP_PATH}" ]]; then
  echo "error: app bundle not found at ${APP_PATH}" >&2
  exit 1
fi

STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/smartclose-dmg.XXXXXX")"
trap 'rm -rf "${STAGING_DIR}"' EXIT

cp -R "${APP_PATH}" "${STAGING_DIR}/"
ln -s /Applications "${STAGING_DIR}/Applications"
rm -f "${OUTPUT_DMG}"

hdiutil create \
  -volname "${VOLUME_NAME}" \
  -srcfolder "${STAGING_DIR}" \
  -fs HFS+ \
  -format UDZO \
  "${OUTPUT_DMG}"
