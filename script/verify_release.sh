#!/usr/bin/env bash

set -euo pipefail

ASSET_NAME="TypeSwitch-macOS-universal.zip"
CHECKSUMS_NAME="checksums.txt"
APPCAST_NAME="appcast.xml"
EXPECTED_MINIMUM_SYSTEM_VERSION="14.0"
EXPECTED_FEED_URL="https://github.com/ygsgdbd/TypeSwitch/releases/latest/download/appcast.xml"
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
MODE="${1:-}"
RELEASE_TAG="${2:-}"
TEMP_DIRS=()
VERIFIED_BUILD=""
VERIFIED_SHA256=""
NEW_TEMP_DIR=""

cleanup() {
  local path
  for path in "${TEMP_DIRS[@]}"; do
    rm -rf "$path"
  done
}
trap cleanup EXIT

new_temp_dir() {
  NEW_TEMP_DIR=$(mktemp -d)
  TEMP_DIRS+=("$NEW_TEMP_DIR")
}

write_summary() {
  local status="$1"
  local detail="$2"

  case "$status" in
    published_and_synced|published_homebrew_pending|publish_failed) ;;
    *) echo "Invalid release summary status: $status" >&2; exit 1 ;;
  esac

  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    {
      echo "### Release distribution status"
      echo
      echo "- Status: \`${status}\`"
      echo "- Tag: \`${RELEASE_TAG:-unknown}\`"
      echo "- Details: ${detail}"
      echo
    } >> "$GITHUB_STEP_SUMMARY"
  fi
}

fail() {
  local message="$1"
  local status="${2:-publish_failed}"
  echo "::error title=Release verification failed::${message}" >&2
  write_summary "$status" "$message"
  exit 1
}

usage() {
  cat >&2 <<'EOF'
Usage:
  script/verify_release.sh local vX.Y.Z [artifact-directory]
  script/verify_release.sh remote vX.Y.Z <owner/repository> <expected-sha256>
EOF
  exit 2
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Required command is unavailable: $1"
}

sha256_file() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    fail "Neither shasum nor sha256sum is available."
  fi
}

file_size() {
  stat -f '%z' "$1"
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
RUBY
}

verify_local_artifacts() {
  local artifact_dir="$1"
  local zip_path="${artifact_dir}/${ASSET_NAME}"
  local checksums_path="${artifact_dir}/${CHECKSUMS_NAME}"
  local appcast_path="${artifact_dir}/${APPCAST_NAME}"
  local expected_sha actual_sha expected_size expected_url version checksum_count
  local extract_dir app_path info_plist binary_path bundle_version build minimum_system_version feed_url architectures

  require_command ditto
  require_command lipo
  require_command plutil
  require_command ruby

  for path in "$zip_path" "$checksums_path" "$appcast_path"; do
    [[ -s "$path" ]] || fail "Missing or empty release artifact: ${path}"
  done

  checksum_count=$(awk -v asset="$ASSET_NAME" '
    $1 ~ /^[[:xdigit:]]{64}$/ && ($2 == asset || $2 == "*" asset) { count++ }
    END { print count + 0 }
  ' "$checksums_path")
  [[ "$checksum_count" == "1" ]] || fail "${CHECKSUMS_NAME} must contain exactly one checksum for ${ASSET_NAME}; found ${checksum_count}."

  expected_sha=$(awk -v asset="$ASSET_NAME" '
    $1 ~ /^[[:xdigit:]]{64}$/ && ($2 == asset || $2 == "*" asset) { print tolower($1) }
  ' "$checksums_path")
  actual_sha=$(sha256_file "$zip_path")
  [[ "$actual_sha" == "$expected_sha" ]] || fail "Checksum mismatch for ${ASSET_NAME}: expected ${expected_sha}, got ${actual_sha}."

  new_temp_dir
  extract_dir="$NEW_TEMP_DIR"
  ditto -x -k "$zip_path" "$extract_dir" || fail "Unable to extract ${ASSET_NAME}."
  app_path="${extract_dir}/TypeSwitch.app"
  info_plist="${app_path}/Contents/Info.plist"
  binary_path="${app_path}/Contents/MacOS/TypeSwitch"
  [[ -f "$info_plist" ]] || fail "Release archive is missing TypeSwitch.app/Contents/Info.plist."
  [[ -f "$binary_path" ]] || fail "Release archive is missing the TypeSwitch executable."

  version="${RELEASE_TAG#v}"
  bundle_version=$(plist_value CFBundleShortVersionString "$info_plist")
  build=$(plist_value CFBundleVersion "$info_plist")
  minimum_system_version=$(plist_value LSMinimumSystemVersion "$info_plist")
  feed_url=$(plist_value SUFeedURL "$info_plist")
  [[ "$bundle_version" == "$version" ]] || fail "Bundle short version mismatch: expected ${version}, got ${bundle_version}."
  [[ -n "$build" ]] || fail "Bundle build version must not be empty."
  [[ "$minimum_system_version" == "$EXPECTED_MINIMUM_SYSTEM_VERSION" ]] || fail "Minimum system version mismatch: expected ${EXPECTED_MINIMUM_SYSTEM_VERSION}, got ${minimum_system_version}."
  [[ "$feed_url" == "$EXPECTED_FEED_URL" ]] || fail "Sparkle feed URL mismatch: expected ${EXPECTED_FEED_URL}, got ${feed_url}."

  architectures=$(lipo -archs "$binary_path") || fail "Unable to inspect TypeSwitch binary architectures."
  [[ " $architectures " == *" arm64 "* && " $architectures " == *" x86_64 "* ]] || fail "Expected universal binary with arm64 and x86_64, got: ${architectures}."

  expected_size=$(file_size "$zip_path")
  expected_url="https://github.com/ygsgdbd/TypeSwitch/releases/download/${RELEASE_TAG}/${ASSET_NAME}"
  verify_appcast "$appcast_path" "$version" "$build" "$expected_url" "$expected_size" || fail "${APPCAST_NAME} does not match the app bundle and release artifact."

  VERIFIED_BUILD="$build"
  VERIFIED_SHA256="$actual_sha"
  echo "Verified ${RELEASE_TAG}: ${ASSET_NAME} (${actual_sha}), build ${build}, architectures ${architectures}."
}

verify_release_metadata() {
  local repository="$1"
  local release_json

  release_json=$(gh api "repos/${repository}/releases/tags/${RELEASE_TAG}") || fail "Unable to load published GitHub Release ${RELEASE_TAG}."
  if ! printf '%s' "$release_json" | ruby -rjson -e '
    release = JSON.parse(STDIN.read)
    expected_tag = ARGV.fetch(0)
    abort "GitHub Release tag does not match" unless release["tag_name"] == expected_tag
    abort "GitHub Release is still a draft" unless release["draft"] == false
    abort "GitHub Release is marked as a prerelease" unless release["prerelease"] == false
  ' "$RELEASE_TAG"; then
    fail "GitHub Release ${RELEASE_TAG} is not a published production release."
  fi
}

verify_latest_appcast() {
  local repository="$1"
  local artifact_dir="$2"
  local latest_appcast="${artifact_dir}/latest-appcast.xml"
  local version="${RELEASE_TAG#v}"
  local expected_url="https://github.com/ygsgdbd/TypeSwitch/releases/download/${RELEASE_TAG}/${ASSET_NAME}"
  local expected_size

  expected_size=$(file_size "${artifact_dir}/${ASSET_NAME}")
  curl -fsSL -o "$latest_appcast" "https://github.com/${repository}/releases/latest/download/${APPCAST_NAME}" || fail "Unable to download the latest appcast endpoint."
  verify_appcast "$latest_appcast" "$version" "$VERIFIED_BUILD" "$expected_url" "$expected_size" || fail "The latest appcast endpoint does not point to ${RELEASE_TAG}."
}

verify_homebrew_cask() {
  local artifact_dir="$1"
  local cask_path="${artifact_dir}/typeswitch.rb"
  local original_path="${artifact_dir}/typeswitch.original.rb"

  gh api \
    -H "Accept: application/vnd.github.raw+json" \
    "repos/ygsgdbd/homebrew-tap/contents/Casks/typeswitch.rb" \
    > "$cask_path" || fail "Unable to read the published Homebrew cask." published_homebrew_pending
  cp "$cask_path" "$original_path"

  if ! ruby "${SCRIPT_DIR}/update_homebrew_cask.rb" "$cask_path" "$RELEASE_TAG" "$VERIFIED_SHA256" >/dev/null; then
    fail "Published Homebrew cask has an invalid structure." published_homebrew_pending
  fi
  cmp -s "$original_path" "$cask_path" || fail "Published Homebrew cask does not match ${RELEASE_TAG} and its Release checksum." published_homebrew_pending
}

[[ "$RELEASE_TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "Release tag must use strict vX.Y.Z format; got ${RELEASE_TAG:-<empty>}."

case "$MODE" in
  local)
    [[ $# -le 3 ]] || usage
    verify_local_artifacts "${3:-.}"
    ;;
  remote)
    [[ $# -eq 4 ]] || usage
    require_command curl
    require_command gh
    repository="$3"
    [[ "$repository" =~ ^[^/]+/[^/]+$ ]] || fail "Repository must use owner/name format; got ${repository:-<empty>}."
    expected_sha256=$(printf '%s' "$4" | tr '[:upper:]' '[:lower:]')
    [[ "$expected_sha256" =~ ^[0-9a-f]{64}$ ]] || fail "Expected SHA-256 must contain exactly 64 hexadecimal characters."

    verify_release_metadata "$repository"
    new_temp_dir
    download_dir="$NEW_TEMP_DIR"
    for asset in "$ASSET_NAME" "$CHECKSUMS_NAME" "$APPCAST_NAME"; do
      gh release download "$RELEASE_TAG" --repo "$repository" --dir "$download_dir" --pattern "$asset" || fail "Unable to download ${asset} from ${RELEASE_TAG}."
    done

    remote_sha256=$(sha256_file "${download_dir}/${ASSET_NAME}")
    [[ "$remote_sha256" == "$expected_sha256" ]] || fail "Published ${ASSET_NAME} checksum mismatch: expected ${expected_sha256}, got ${remote_sha256}."

    verify_local_artifacts "$download_dir"
    gh attestation verify "${download_dir}/${ASSET_NAME}" --repo "$repository" >/dev/null || fail "Artifact attestation verification failed for ${ASSET_NAME}."
    verify_latest_appcast "$repository" "$download_dir"
    verify_homebrew_cask "$download_dir"
    write_summary published_and_synced "GitHub Release, latest appcast, attestation, and Homebrew cask are consistent."
    ;;
  *)
    usage
    ;;
esac
