#!/usr/bin/env bash
# Archives the app in Release and uploads it to App Store Connect for TestFlight (TT-154, D47).
# Run by .github/workflows/testflight.yml on a GitHub macOS runner.
#
#   ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8   App Store Connect API key with the Admin role (secrets)
#   METROLINX_API_KEY                       optional (D36); without it the build shows the timetable only
#   BUILD_NUMBER                            CFBundleVersion, unique per upload (the workflow's run number)
#   DRY_RUN=1                               archive without signing and stop: checks that Release compiles
#
# Signing: scripts/asc-signing.mjs creates an Apple Distribution certificate and an App Store profile for this run.
# They are revoked here if the run fails, and by the workflow's second job once the build is processed.
set -euo pipefail
cd "$(dirname "$0")/.."

TEAM_ID=886B9D4D6M
WORK="${RUNNER_TEMP:-$(mktemp -d)}/testflight"
ARCHIVE="$WORK/TrainTimes.xcarchive"
rm -rf "$WORK" && mkdir -p "$WORK"

FORMATTER=(cat)
if command -v xcbeautify >/dev/null 2>&1; then
  FORMATTER=(xcbeautify)
  [[ -n "${GITHUB_ACTIONS:-}" ]] && FORMATTER+=(--renderer github-actions)
fi
xcodebuild -version

ARCHIVE_ARGS=(
  -project TrainTimes.xcodeproj -scheme TrainTimes -configuration Release
  -destination 'generic/platform=iOS' -archivePath "$ARCHIVE"
  -skipMacroValidation -skipPackagePluginValidation
)

if [[ "${DRY_RUN:-}" == 1 ]]; then
  xcodebuild archive "${ARCHIVE_ARGS[@]}" CODE_SIGNING_ALLOWED=NO 2>&1 | "${FORMATTER[@]}"
  echo "Release archive builds (unsigned dry run)."
  exit 0
fi

for name in ASC_KEY_ID ASC_ISSUER_ID ASC_KEY_P8 BUILD_NUMBER; do
  [[ -n "${!name:-}" ]] || { echo "::error::Missing $name. Add it under Settings › Secrets and variables › Actions."; exit 1; }
done

# D36: the Metrolinx key reaches the app through the git-ignored Config/Secrets.xcconfig.
if [[ -n "${METROLINX_API_KEY:-}" ]]; then
  printf 'METROLINX_API_KEY = %s\n' "$METROLINX_API_KEY" > Config/Secrets.xcconfig
  echo "Built with the Metrolinx key: live status and line notices on."
else
  echo "::warning::No METROLINX_API_KEY secret: this build shows the timetable only, with no live status or line notices."
fi

KEY_PATH="$WORK/AuthKey_$ASC_KEY_ID.p8"
printf '%s\n' "$ASC_KEY_P8" > "$KEY_PATH"
KEYCHAIN="$WORK/signing.keychain-db"
KEYCHAIN_PASSWORD=$(uuidgen)
OLD_KEYCHAINS=$(security list-keychains -d user | xargs)
PROFILE_DIRS=("$HOME/Library/MobileDevice/Provisioning Profiles" "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles")

finish() {
  local status=$?
  # On failure revoke now; on success the workflow revokes once TestFlight has processed the build.
  [[ $status -ne 0 && -f "$WORK/state.json" ]] && node scripts/asc-signing.mjs cleanup "$WORK" || true
  security list-keychains -d user -s $OLD_KEYCHAINS || true
  security delete-keychain "$KEYCHAIN" 2>/dev/null || true
  [[ -n "${PROFILE_UUID:-}" ]] && for dir in "${PROFILE_DIRS[@]}"; do rm -f "$dir/$PROFILE_UUID.mobileprovision"; done
  rm -f "$KEY_PATH" "$WORK"/*.pem "$WORK"/*.p12
  exit $status
}
trap finish EXIT

# A fresh key pair and certificate for this run. /usr/bin/openssl is LibreSSL, whose PKCS#12 files `security` reads.
/usr/bin/openssl req -new -newkey rsa:2048 -nodes -keyout "$WORK/key.pem" -out "$WORK/csr.pem" -subj "/CN=Train Times TestFlight/C=CA" 2>/dev/null
node scripts/asc-signing.mjs setup "$WORK"
PROFILE_NAME=$(node -p "require('$WORK/state.json').profileName")
PROFILE_UUID=$(node -p "require('$WORK/state.json').profileUuid")

P12_PASSWORD=$(uuidgen)
/usr/bin/openssl x509 -inform DER -in "$WORK/cert.cer" -out "$WORK/cert.pem"
/usr/bin/openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" -out "$WORK/signing.p12" \
  -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -passout "pass:$P12_PASSWORD"

security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security import "$WORK/signing.p12" -k "$KEYCHAIN" -f pkcs12 -P "$P12_PASSWORD" -T /usr/bin/codesign -T /usr/bin/security
curl -fsSL https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer -o "$WORK/wwdr.cer"
security import "$WORK/wwdr.cer" -k "$KEYCHAIN" >/dev/null 2>&1 || true
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null
security list-keychains -d user -s "$KEYCHAIN" $OLD_KEYCHAINS
for dir in "${PROFILE_DIRS[@]}"; do
  mkdir -p "$dir" && cp "$WORK/profile.mobileprovision" "$dir/$PROFILE_UUID.mobileprovision"
done

xcodebuild archive "${ARCHIVE_ARGS[@]}" \
  DEVELOPMENT_TEAM="$TEAM_ID" CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Apple Distribution" \
  PROVISIONING_PROFILE_SPECIFIER="$PROFILE_NAME" OTHER_CODE_SIGN_FLAGS="--keychain $KEYCHAIN" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" 2>&1 | "${FORMATTER[@]}"

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleShortVersionString' "$ARCHIVE/Info.plist")
echo "Archived Train Times $VERSION ($BUILD_NUMBER)"

cat > "$WORK/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>Apple Distribution</string>
  <key>provisioningProfiles</key>
  <dict><key>ca.traintimes.TrainTimes</key><string>$PROFILE_NAME</string></dict>
  <key>manageAppVersionAndBuildNumber</key><false/>
  <key>uploadSymbols</key><true/>
</dict>
</plist>
PLIST

# Uploads to App Store Connect with the API key; TestFlight then processes the build (the workflow's second job waits).
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$WORK/export" -exportOptionsPlist "$WORK/ExportOptions.plist" \
  -allowProvisioningUpdates -authenticationKeyPath "$KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
  2>&1 | "${FORMATTER[@]}"

[[ -n "${GITHUB_OUTPUT:-}" ]] && echo "build=$BUILD_NUMBER" >> "$GITHUB_OUTPUT"
echo "Uploaded Train Times $VERSION ($BUILD_NUMBER) to App Store Connect."
