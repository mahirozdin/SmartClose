#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="${PROJECT_PATH:-${ROOT_DIR}/SmartClose.xcodeproj}"
SCHEME="${SCHEME:-SmartClose}"
CONFIGURATION="${CONFIGURATION:-Release}"
TEAM_ID="${SMARTCLOSE_TEAM_ID:-WWRZ5CG3DW}"
NOTARY_PROFILE="${SMARTCLOSE_NOTARY_PROFILE:-smartclose-notary}"
ARCHIVE_PATH="${ARCHIVE_PATH:-${ROOT_DIR}/build/archives/SmartClose.xcarchive}"
EXPORT_PATH="${EXPORT_PATH:-${ROOT_DIR}/build/export}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-${ROOT_DIR}/build/DerivedDataRelease}"

VERSION="$(sed -n 's/.*MARKETING_VERSION = \([^;]*\);/\1/p' "${ROOT_DIR}/SmartClose.xcodeproj/project.pbxproj" | head -n 1)"
BUILD_NUMBER="$(sed -n 's/.*CURRENT_PROJECT_VERSION = \([^;]*\);/\1/p' "${ROOT_DIR}/SmartClose.xcodeproj/project.pbxproj" | head -n 1)"
DIST_DIR="${DIST_DIR:-${ROOT_DIR}/dist/${VERSION}}"
ZIP_PATH="${DIST_DIR}/SmartClose-${VERSION}.zip"
DMG_PATH="${DIST_DIR}/SmartClose-${VERSION}.dmg"
CHECKSUM_PATH="${DIST_DIR}/SmartClose-${VERSION}-SHA256.txt"
EXPORT_OPTIONS_PLIST="$(mktemp "${TMPDIR:-/tmp}/smartclose-export-options.XXXXXX.plist")"
SUBMISSION_ZIP="$(mktemp "${TMPDIR:-/tmp}/smartclose-notary-submit.XXXXXX.zip")"
trap 'rm -f "${EXPORT_OPTIONS_PLIST}" "${SUBMISSION_ZIP}"' EXIT

mkdir -p "${DIST_DIR}" "$(dirname "${ARCHIVE_PATH}")" "${EXPORT_PATH}" "${DERIVED_DATA_PATH}"
rm -rf "${ARCHIVE_PATH}" "${EXPORT_PATH}"

cat > "${EXPORT_OPTIONS_PLIST}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>destination</key>
  <string>export</string>
  <key>method</key>
  <string>developer-id</string>
  <key>signingStyle</key>
  <string>automatic</string>
  <key>teamID</key>
  <string>${TEAM_ID}</string>
</dict>
</plist>
EOF

echo "==> SmartClose ${VERSION} (${BUILD_NUMBER})"
echo "==> Checking local Developer ID identities"
IDENTITIES="$(security find-identity -v -p codesigning || true)"
echo "${IDENTITIES}" | rg "Developer ID Application|Apple Development|Apple Distribution" || true

if ! grep -q "Developer ID Application: .*(${TEAM_ID})" <<< "${IDENTITIES}"; then
  echo "error: missing 'Developer ID Application' certificate for team ${TEAM_ID}" >&2
  echo "hint: open Xcode > Settings > Accounts > Manage Certificates and create/download 'Developer ID Application'." >&2
  exit 1
fi

echo "==> Archiving app"
xcodebuild archive \
  -project "${PROJECT_PATH}" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  -destination "generic/platform=macOS" \
  -archivePath "${ARCHIVE_PATH}" \
  -derivedDataPath "${DERIVED_DATA_PATH}" \
  -allowProvisioningUpdates

echo "==> Exporting Developer ID app"
xcodebuild -exportArchive \
  -archivePath "${ARCHIVE_PATH}" \
  -exportPath "${EXPORT_PATH}" \
  -exportOptionsPlist "${EXPORT_OPTIONS_PLIST}" \
  -allowProvisioningUpdates

APP_PATH="$(find "${EXPORT_PATH}" -maxdepth 1 -name '*.app' -print -quit)"
if [[ -z "${APP_PATH}" ]]; then
  echo "error: exported app bundle not found in ${EXPORT_PATH}" >&2
  exit 1
fi

echo "==> Verifying exported signature"
codesign --verify --deep --strict --verbose=2 "${APP_PATH}"
SIGNATURE_INFO="$(codesign -dv --verbose=4 "${APP_PATH}" 2>&1)"
echo "${SIGNATURE_INFO}"
if ! grep -q "Authority=Developer ID Application" <<< "${SIGNATURE_INFO}"; then
  echo "error: exported app is not signed with a Developer ID Application certificate" >&2
  exit 1
fi
if ! grep -q "Runtime Version=" <<< "${SIGNATURE_INFO}"; then
  echo "error: hardened runtime is not enabled on the exported app" >&2
  exit 1
fi
if ! grep -q "TeamIdentifier=${TEAM_ID}" <<< "${SIGNATURE_INFO}"; then
  echo "error: exported app TeamIdentifier does not match expected team ${TEAM_ID}" >&2
  exit 1
fi

echo "==> Notarizing app bundle"
ditto -c -k --sequesterRsrc --keepParent "${APP_PATH}" "${SUBMISSION_ZIP}"
xcrun notarytool submit "${SUBMISSION_ZIP}" --keychain-profile "${NOTARY_PROFILE}" --wait
xcrun stapler staple "${APP_PATH}"

echo "==> Creating ZIP artifact"
rm -f "${ZIP_PATH}"
ditto -c -k --sequesterRsrc --keepParent "${APP_PATH}" "${ZIP_PATH}"

echo "==> Creating DMG artifact"
"${ROOT_DIR}/scripts/create_dmg.sh" "${APP_PATH}" "${DMG_PATH}" "SmartClose"

echo "==> Notarizing DMG"
xcrun notarytool submit "${DMG_PATH}" --keychain-profile "${NOTARY_PROFILE}" --wait
xcrun stapler staple "${DMG_PATH}"

echo "==> Writing checksums"
shasum -a 256 "${ZIP_PATH}" "${DMG_PATH}" > "${CHECKSUM_PATH}"

echo "==> Release artifacts ready"
echo "ZIP: ${ZIP_PATH}"
echo "DMG: ${DMG_PATH}"
echo "SHA256: ${CHECKSUM_PATH}"
