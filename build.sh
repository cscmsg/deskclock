#!/usr/bin/env bash
set -euo pipefail

# ----------------------------------------------------------------------------
# Configuration (edit these to rename / rebrand the app).
# ----------------------------------------------------------------------------
APP_NAME="DeskClock"
BUNDLE_ID="com.cscmsg.deskclock"
SHORT_VERSION="1.2.0"   # CFBundleShortVersionString (marketing version)
BUILD_VERSION="3"       # CFBundleVersion (build number)
# ----------------------------------------------------------------------------

usage() {
  cat <<USAGE
Usage: ./build.sh [--notarize]

  (no flags)   Build ${APP_NAME}.app (Apple silicon + Intel) and sign it: with a
               Developer ID if one is configured, ad-hoc otherwise.
  --notarize   Also notarize it with Apple, staple the ticket, check Gatekeeper
               accepts it, and write dist/${APP_NAME}-${SHORT_VERSION}.zip.

Signing identity: the SHA-1 in SIGN_IDENTITY, or in a .signing-identity file
next to this script (gitignored). With exactly one Developer ID Application
certificate in the keychain, that one is used without either.

Notary credentials: a notarytool keychain profile, named by NOTARY_PROFILE
(default "notary"). Create it once with:
    xcrun notarytool store-credentials notary --apple-id <you> --team-id <TEAMID>
USAGE
}

NOTARIZE=0
for arg in "$@"; do
  case "$arg" in
    --notarize) NOTARIZE=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $arg" >&2; usage >&2; exit 2 ;;
  esac
done

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

ARCHS=(--arch arm64 --arch x86_64)

echo "==> Building ${APP_NAME} (release, universal)…"
swift build -c release "${ARCHS[@]}"

BIN_PATH="$(swift build -c release "${ARCHS[@]}" --show-bin-path)"
APP_DIR="${ROOT}/${APP_NAME}.app"
MACOS_DIR="${APP_DIR}/Contents/MacOS"
RES_DIR="${APP_DIR}/Contents/Resources"

echo "==> Assembling ${APP_NAME}.app…"
rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}" "${RES_DIR}"

cp "${BIN_PATH}/${APP_NAME}" "${MACOS_DIR}/${APP_NAME}"

cat > "${APP_DIR}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleShortVersionString</key>
    <string>${SHORT_VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

# Choosing a signing identity -- by SHA-1, never by name. A keychain can hold
# several Developer ID certificates with the same Common Name, and
# `codesign --sign "<name>"` then fails as ambiguous. With several and none
# named, refuse to guess: a build signed with the wrong certificate looks
# completely normal until someone's Gatekeeper rejects it.
#
# The trailing `|| true` is load-bearing under pipefail: with no certificate
# installed grep exits 1 and would abort the script right after the build.
CANDIDATES="$(security find-identity -v -p codesigning 2>/dev/null \
  | grep '"Developer ID Application' || true)"
CANDIDATE_COUNT="$(printf '%s' "$CANDIDATES" | grep -c . || true)"

if [ -z "${SIGN_IDENTITY:-}" ] && [ -f .signing-identity ]; then
  SIGN_IDENTITY="$(tr -d '[:space:]' < .signing-identity)"
fi

if [ -n "${SIGN_IDENTITY:-}" ]; then
  IDENTITY="$SIGN_IDENTITY"
elif [ "$CANDIDATE_COUNT" = "1" ]; then
  IDENTITY="$(printf '%s' "$CANDIDATES" | awk '{print $2}')"
elif [ "${CANDIDATE_COUNT:-0}" -gt 1 ]; then
  echo "Multiple Developer ID certificates found; refusing to pick one:" >&2
  printf '%s\n' "$CANDIDATES" | sed 's/^/    /' >&2
  echo >&2
  echo "Put the SHA-1 of the one you want in .signing-identity, or set SIGN_IDENTITY." >&2
  exit 1
else
  IDENTITY=""
fi

if [ -n "$IDENTITY" ]; then
  echo "==> Signing with Developer ID (hardened runtime)…"
  # Hardened runtime and a secure timestamp are both required for notarization.
  # No --deep: the bundle holds a single executable and nothing nested to sign.
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "${APP_DIR}"
  echo "    $(codesign -dvv "${APP_DIR}" 2>&1 | grep '^Authority' | head -1)"
else
  if [ "$NOTARIZE" = 1 ]; then
    echo "--notarize needs a Developer ID certificate, and none is configured." >&2
    exit 1
  fi
  echo "==> Ad-hoc signing (no Developer ID configured)…"
  codesign --force --sign - "${APP_DIR}"
fi
codesign --verify --strict "${APP_DIR}"

if [ "$NOTARIZE" = 1 ]; then
  PROFILE="${NOTARY_PROFILE:-notary}"
  DIST="${ROOT}/dist"
  ZIP="${DIST}/${APP_NAME}-${SHORT_VERSION}.zip"
  WORK="$(mktemp -d)"
  trap 'rm -rf "$WORK"' EXIT

  echo "==> Submitting to Apple's notary service (profile: ${PROFILE})…"
  ditto -c -k --keepParent "${APP_DIR}" "${WORK}/submit.zip"
  # `|| true` so a rejected or failed submission reaches the status check below
  # and prints Apple's log, instead of set -e ending the script silently here.
  xcrun notarytool submit "${WORK}/submit.zip" --keychain-profile "$PROFILE" \
    --wait --output-format json > "${WORK}/result.json" || true

  STATUS="$(plutil -extract status raw -o - "${WORK}/result.json" 2>/dev/null || true)"
  SUBMISSION_ID="$(plutil -extract id raw -o - "${WORK}/result.json" 2>/dev/null || true)"
  if [ "$STATUS" != "Accepted" ]; then
    echo "Notarization did not succeed (status: ${STATUS:-unreadable})." >&2
    cat "${WORK}/result.json" >&2
    if [ -n "$SUBMISSION_ID" ]; then
      echo "Apple's log for submission ${SUBMISSION_ID}:" >&2
      xcrun notarytool log "$SUBMISSION_ID" --keychain-profile "$PROFILE" >&2 || true
    fi
    exit 1
  fi
  echo "    Accepted (submission ${SUBMISSION_ID})"

  echo "==> Stapling the ticket…"
  xcrun stapler staple "${APP_DIR}"
  xcrun stapler validate "${APP_DIR}"

  # The check that matters. A build can sign cleanly and still be rejected
  # here, which is exactly what a user would hit on first launch.
  echo "==> Asking Gatekeeper…"
  ASSESSMENT="$(spctl --assess --type execute --verbose=4 "${APP_DIR}" 2>&1)" || {
    echo "$ASSESSMENT" >&2
    echo "Gatekeeper rejected the notarized app." >&2
    exit 1
  }
  echo "    ${ASSESSMENT}"
  case "$ASSESSMENT" in
    *"source=Notarized Developer ID"*) ;;
    *) echo "Gatekeeper accepted it, but not as a notarized Developer ID app." >&2; exit 1 ;;
  esac

  # Zip after stapling, so the ticket travels with the download and the app
  # opens without a network check.
  mkdir -p "$DIST"
  rm -f "$ZIP"
  ditto -c -k --keepParent "${APP_DIR}" "$ZIP"
  echo "==> Release artifact:"
  echo "    ${ZIP}"
  echo "    sha256 $(shasum -a 256 "$ZIP" | awk '{print $1}')"
fi

echo "==> Done."
echo "    ${APP_DIR}"
echo "    Run with:  open \"${APP_DIR}\""
