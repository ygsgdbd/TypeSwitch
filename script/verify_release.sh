#!/usr/bin/env bash

set -euo pipefail

ASSET_NAME="TypeSwitch-macOS-universal.zip"
CHECKSUMS_NAME="checksums.txt"
APPCAST_NAME="appcast.xml"
EXPECTED_MINIMUM_SYSTEM_VERSION="14.0"
EXPECTED_FEED_URL="https://github.com/ygsgdbd/TypeSwitch/releases/latest/download/appcast.xml"
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
RELEASE_TAG="${1:-}"
ARTIFACT_DIR="${2:-.}"
TEMP_DIR=""

cleanup() {
  if [[ -n "$TEMP_DIR" ]]; then
    rm -rf "$TEMP_DIR"
  fi
}
trap cleanup EXIT

fail() {
  echo "::error title=Release verification failed::$1" >&2
  exit 1
}

usage() {
  echo "Usage: script/verify_release.sh vX.Y.Z [artifact-directory]" >&2
  exit 2
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Required command is unavailable: $1"
}

sha256_file() {
  shasum -a 256 "$1" | awk '{print $1}'
}

plist_value() {
  plutil -extract "$1" raw -o - "$2" 2>/dev/null || fail "Info.plist is missing required key $1."
}

verify_appcast() {
  local appcast_path="$1"
  local expected_version="$2"
  local expected_build="$3"
  local expected_url="$4"
  local expected_size="$5"

  ruby -rrexml/document -rrexml/xpath - "$appcast_path" "$expected_version" "$expected_build" "$expected_url" "$expected_size" <<'RUBY'
path, expected_version, expected_build, expected_url, expected_size = ARGV
sparkle = { "sparkle" => "http://www.andymatuschak.org/xml-namespaces/sparkle" }

begin
  document = REXML::Document.new(File.read(path))
rescue StandardError => error
  abort "Invalid appcast XML: #{error.message}"
end

items = REXML::XPath.match(document, "/rss/channel/item")
abort "Expected exactly one appcast item, found #{items.length}" unless items.length == 1

item = items.first
enclosure = REXML::XPath.first(item, "enclosure")
abort "Appcast item is missing its enclosure" unless enclosure

version = REXML::XPath.first(item, "sparkle:shortVersionString", sparkle)&.text
version ||= enclosure.attributes["sparkle:shortVersionString"]
build = REXML::XPath.first(item, "sparkle:version", sparkle)&.text
build ||= enclosure.attributes["sparkle:version"]
checks = {
  "short version" => [version, expected_version],
  "build" => [build, expected_build],
  "download URL" => [enclosure.attributes["url"], expected_url],
  "file length" => [enclosure.attributes["length"], expected_size],
}
checks.each do |label, (actual, expected)|
  abort "Appcast #{label} mismatch: expected #{expected.inspect}, got #{actual.inspect}" unless actual == expected
end

signature = enclosure.attributes["sparkle:edSignature"]
abort "Appcast enclosure is missing the Sparkle EdDSA signature" if signature.nil? || signature.empty?
puts signature
RUBY
}

[[ $# -ge 1 && $# -le 2 ]] || usage
[[ "$RELEASE_TAG" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] || fail "Release tag must use vX.Y.Z without leading zeros; got ${RELEASE_TAG:-<empty>}."

require_command ditto
require_command lipo
require_command plutil
require_command ruby
require_command shasum

ZIP_PATH="${ARTIFACT_DIR}/${ASSET_NAME}"
CHECKSUMS_PATH="${ARTIFACT_DIR}/${CHECKSUMS_NAME}"
APPCAST_PATH="${ARTIFACT_DIR}/${APPCAST_NAME}"
for path in "$ZIP_PATH" "$CHECKSUMS_PATH" "$APPCAST_PATH"; do
  [[ -s "$path" ]] || fail "Missing or empty release artifact: $path"
done

CHECKSUM_COUNT=$(awk -v asset="$ASSET_NAME" '
  $1 ~ /^[[:xdigit:]]{64}$/ && ($2 == asset || $2 == "*" asset) { count++ }
  END { print count + 0 }
' "$CHECKSUMS_PATH")
[[ "$CHECKSUM_COUNT" == "1" ]] || fail "${CHECKSUMS_NAME} must contain exactly one checksum for ${ASSET_NAME}; found ${CHECKSUM_COUNT}."

EXPECTED_SHA256=$(awk -v asset="$ASSET_NAME" '
  $1 ~ /^[[:xdigit:]]{64}$/ && ($2 == asset || $2 == "*" asset) { print tolower($1) }
' "$CHECKSUMS_PATH")
ACTUAL_SHA256=$(sha256_file "$ZIP_PATH")
[[ "$ACTUAL_SHA256" == "$EXPECTED_SHA256" ]] || fail "Checksum mismatch for ${ASSET_NAME}: expected ${EXPECTED_SHA256}, got ${ACTUAL_SHA256}."

TEMP_DIR=$(mktemp -d)
ditto -x -k "$ZIP_PATH" "$TEMP_DIR" || fail "Unable to extract ${ASSET_NAME}."
APP_PATH="${TEMP_DIR}/TypeSwitch.app"
INFO_PLIST="${APP_PATH}/Contents/Info.plist"
BINARY_PATH="${APP_PATH}/Contents/MacOS/TypeSwitch"
[[ -f "$INFO_PLIST" ]] || fail "Release archive is missing TypeSwitch.app/Contents/Info.plist."
[[ -f "$BINARY_PATH" ]] || fail "Release archive is missing the TypeSwitch executable."

VERSION="${RELEASE_TAG#v}"
BUNDLE_VERSION=$(plist_value CFBundleShortVersionString "$INFO_PLIST")
BUILD=$(plist_value CFBundleVersion "$INFO_PLIST")
MINIMUM_SYSTEM_VERSION=$(plist_value LSMinimumSystemVersion "$INFO_PLIST")
FEED_URL=$(plist_value SUFeedURL "$INFO_PLIST")
PUBLIC_KEY=$(plist_value SUPublicEDKey "$INFO_PLIST")
[[ "$BUNDLE_VERSION" == "$VERSION" ]] || fail "Bundle short version mismatch: expected ${VERSION}, got ${BUNDLE_VERSION}."
[[ -n "$BUILD" ]] || fail "Bundle build version must not be empty."
[[ "$MINIMUM_SYSTEM_VERSION" == "$EXPECTED_MINIMUM_SYSTEM_VERSION" ]] || fail "Minimum system version mismatch: expected ${EXPECTED_MINIMUM_SYSTEM_VERSION}, got ${MINIMUM_SYSTEM_VERSION}."
[[ "$FEED_URL" == "$EXPECTED_FEED_URL" ]] || fail "Sparkle feed URL mismatch: expected ${EXPECTED_FEED_URL}, got ${FEED_URL}."

ARCHITECTURES=$(lipo -archs "$BINARY_PATH") || fail "Unable to inspect TypeSwitch binary architectures."
[[ " $ARCHITECTURES " == *" arm64 "* && " $ARCHITECTURES " == *" x86_64 "* ]] || fail "Expected arm64 and x86_64, got ${ARCHITECTURES}."

EXPECTED_SIZE=$(stat -f '%z' "$ZIP_PATH")
EXPECTED_URL="https://github.com/ygsgdbd/TypeSwitch/releases/download/${RELEASE_TAG}/${ASSET_NAME}"
SIGNATURE=$(verify_appcast "$APPCAST_PATH" "$VERSION" "$BUILD" "$EXPECTED_URL" "$EXPECTED_SIZE") || fail "${APPCAST_NAME} does not match the app bundle and release artifact."

SIGN_UPDATE="${SPARKLE_SIGN_UPDATE:-${SCRIPT_DIR}/../sparkle-tools/bin/sign_update}"
[[ -x "$SIGN_UPDATE" ]] || fail "Sparkle sign_update is unavailable: ${SIGN_UPDATE}"
LEGACY_VERIFICATION_KEY=$(ruby -rbase64 -e '
  public_key = Base64.strict_decode64(ARGV.fetch(0))
  abort "SUPublicEDKey must decode to exactly 32 bytes" unless public_key.bytesize == 32
  STDOUT.write(Base64.strict_encode64(("\0" * 64) + public_key))
' "$PUBLIC_KEY") || fail "Unable to prepare the Sparkle public key for signature verification."
if ! printf '%s' "$LEGACY_VERIFICATION_KEY" | "$SIGN_UPDATE" --ed-key-file - --verify "$ZIP_PATH" "$SIGNATURE" >/dev/null; then
  fail "Appcast EdDSA signature does not match the built app's SUPublicEDKey."
fi

echo "Verified ${RELEASE_TAG}: ${ASSET_NAME} (${ACTUAL_SHA256}), build ${BUILD}, architectures ${ARCHITECTURES}."
