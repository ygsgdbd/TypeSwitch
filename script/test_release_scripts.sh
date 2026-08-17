#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
VERIFY_SCRIPT="${ROOT_DIR}/script/verify_release.sh"
CASK_SCRIPT="${ROOT_DIR}/script/update_homebrew_cask.rb"
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

assert_fails() {
  if "$@" >/dev/null 2>&1; then
    fail "Command unexpectedly succeeded: $*"
  fi
}

sha256_file() {
  shasum -a 256 "$1" | awk '{print $1}'
}

make_artifacts() {
  local dir="$1"
  local tag="$2"
  local version="${tag#v}"
  local plist_version="${FIXTURE_PLIST_VERSION:-$version}"
  local build="${FIXTURE_BUILD-202608170101}"
  local appcast_build="${FIXTURE_APPCAST_BUILD:-$build}"
  local minimum="${FIXTURE_MINIMUM:-14.0}"
  local feed_url="${FIXTURE_FEED_URL:-https://github.com/ygsgdbd/TypeSwitch/releases/latest/download/appcast.xml}"
  local signature="${FIXTURE_SIGNATURE-test-signature}"
  local appcast_layout="${FIXTURE_APPCAST_LAYOUT:-child}"
  local staging="${TEST_DIR}/staging"
  local sha size version_elements enclosure_version_attributes

  rm -rf "$dir" "$staging"
  mkdir -p "$dir" "${staging}/TypeSwitch.app/Contents/MacOS"
  printf 'fixture binary\n' > "${staging}/TypeSwitch.app/Contents/MacOS/TypeSwitch"
  cat > "${staging}/TypeSwitch.app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleShortVersionString</key><string>${plist_version}</string>
  <key>CFBundleVersion</key><string>${build}</string>
  <key>LSMinimumSystemVersion</key><string>${minimum}</string>
  <key>SUFeedURL</key><string>${feed_url}</string>
</dict>
</plist>
EOF
  ditto -c -k --keepParent "${staging}/TypeSwitch.app" "${dir}/TypeSwitch-macOS-universal.zip"
  sha=$(sha256_file "${dir}/TypeSwitch-macOS-universal.zip")
  size=$(stat -f '%z' "${dir}/TypeSwitch-macOS-universal.zip")
  printf '### SHA-256 Checksums\n```\n%s  TypeSwitch-macOS-universal.zip\n```\n' "$sha" > "${dir}/checksums.txt"
  if [[ "$appcast_layout" == "attributes" ]]; then
    version_elements=""
    enclosure_version_attributes=" sparkle:version=\"${appcast_build}\" sparkle:shortVersionString=\"${version}\""
  else
    version_elements="<sparkle:version>${appcast_build}</sparkle:version><sparkle:shortVersionString>${version}</sparkle:shortVersionString>"
    enclosure_version_attributes=""
  fi
  cat > "${dir}/appcast.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
  <channel>
    <item>
      ${version_elements}
      <enclosure url="https://github.com/ygsgdbd/TypeSwitch/releases/download/${tag}/TypeSwitch-macOS-universal.zip" length="${size}" sparkle:edSignature="${signature}"${enclosure_version_attributes} />
    </item>
  </channel>
</rss>
EOF
}

mkdir -p "${TEST_DIR}/bin"
cat > "${TEST_DIR}/bin/lipo" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "${LIPO_ARCHS:-arm64 x86_64}"
EOF
chmod +x "${TEST_DIR}/bin/lipo"

ARTIFACTS="${TEST_DIR}/artifacts"
make_artifacts "$ARTIFACTS" v1.2.3
PATH="${TEST_DIR}/bin:${PATH}" "$VERIFY_SCRIPT" local v1.2.3 "$ARTIFACTS" >/dev/null
FIXTURE_APPCAST_LAYOUT=attributes make_artifacts "$ARTIFACTS" v1.2.3
PATH="${TEST_DIR}/bin:${PATH}" "$VERIFY_SCRIPT" local v1.2.3 "$ARTIFACTS" >/dev/null
make_artifacts "$ARTIFACTS" v1.2.3
assert_fails env PATH="${TEST_DIR}/bin:${PATH}" "$VERIFY_SCRIPT" local 1.2.3 "$ARTIFACTS"

printf 'corruption\n' >> "${ARTIFACTS}/TypeSwitch-macOS-universal.zip"
FAILED_SUMMARY="${TEST_DIR}/failed-summary.md"
if GITHUB_STEP_SUMMARY="$FAILED_SUMMARY" PATH="${TEST_DIR}/bin:${PATH}" "$VERIFY_SCRIPT" local v1.2.3 "$ARTIFACTS" >/dev/null 2>&1; then
  fail "Checksum corruption unexpectedly passed verification."
fi
grep -q '`publish_failed`' "$FAILED_SUMMARY" || fail "Local failure did not report publish_failed."

FIXTURE_PLIST_VERSION=1.2.4 make_artifacts "$ARTIFACTS" v1.2.3
assert_fails env PATH="${TEST_DIR}/bin:${PATH}" "$VERIFY_SCRIPT" local v1.2.3 "$ARTIFACTS"
FIXTURE_BUILD= make_artifacts "$ARTIFACTS" v1.2.3
assert_fails env PATH="${TEST_DIR}/bin:${PATH}" "$VERIFY_SCRIPT" local v1.2.3 "$ARTIFACTS"
FIXTURE_MINIMUM=13.0 make_artifacts "$ARTIFACTS" v1.2.3
assert_fails env PATH="${TEST_DIR}/bin:${PATH}" "$VERIFY_SCRIPT" local v1.2.3 "$ARTIFACTS"
FIXTURE_FEED_URL=https://example.invalid/appcast.xml make_artifacts "$ARTIFACTS" v1.2.3
assert_fails env PATH="${TEST_DIR}/bin:${PATH}" "$VERIFY_SCRIPT" local v1.2.3 "$ARTIFACTS"
make_artifacts "$ARTIFACTS" v1.2.3
assert_fails env PATH="${TEST_DIR}/bin:${PATH}" LIPO_ARCHS=arm64 "$VERIFY_SCRIPT" local v1.2.3 "$ARTIFACTS"
FIXTURE_APPCAST_BUILD=wrong-build make_artifacts "$ARTIFACTS" v1.2.3
assert_fails env PATH="${TEST_DIR}/bin:${PATH}" "$VERIFY_SCRIPT" local v1.2.3 "$ARTIFACTS"
FIXTURE_SIGNATURE= make_artifacts "$ARTIFACTS" v1.2.3
assert_fails env PATH="${TEST_DIR}/bin:${PATH}" "$VERIFY_SCRIPT" local v1.2.3 "$ARTIFACTS"
make_artifacts "$ARTIFACTS" v1.2.3

CASK="${TEST_DIR}/typeswitch.rb"
SHA=$(sha256_file "${ARTIFACTS}/TypeSwitch-macOS-universal.zip")
cat > "$CASK" <<EOF
cask "typeswitch" do
  version "1.2.3"
  sha256 "${SHA}"
  url "https://github.com/ygsgdbd/TypeSwitch/releases/download/v1.2.3/TypeSwitch-macOS-universal.zip"
end
EOF

cat > "${TEST_DIR}/bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$1" == "api" && "$2" == "repos/ygsgdbd/TypeSwitch/releases/tags/v1.2.3" ]]; then
  printf '{"tag_name":"v1.2.3","draft":false,"prerelease":false}\n'
elif [[ "$1 $2" == "release download" ]]; then
  shift 2
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dir) destination="$2"; shift 2 ;;
      --pattern) pattern="$2"; shift 2 ;;
      *) shift ;;
    esac
  done
  cp "${GH_FIXTURE_DIR}/${pattern}" "$destination/"
elif [[ "$1 $2" == "attestation verify" ]]; then
  exit 0
elif [[ "$1" == "api" && "${*: -1}" == "repos/ygsgdbd/homebrew-tap/contents/Casks/typeswitch.rb" ]]; then
  cat "$GH_CASK_PATH"
else
  echo "Unexpected gh invocation: $*" >&2
  exit 1
fi
EOF
cat > "${TEST_DIR}/bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o) destination="$2"; shift 2 ;;
    *) shift ;;
  esac
done
cp "$CURL_APPCAST_PATH" "$destination"
EOF
chmod +x "${TEST_DIR}/bin/gh" "${TEST_DIR}/bin/curl"

REMOTE_SUMMARY="${TEST_DIR}/remote-summary.md"
GITHUB_STEP_SUMMARY="$REMOTE_SUMMARY" \
  GH_FIXTURE_DIR="$ARTIFACTS" \
  GH_CASK_PATH="$CASK" \
  CURL_APPCAST_PATH="${ARTIFACTS}/appcast.xml" \
  PATH="${TEST_DIR}/bin:${PATH}" \
  "$VERIFY_SCRIPT" remote v1.2.3 ygsgdbd/TypeSwitch "$SHA" >/dev/null
grep -q '`published_and_synced`' "$REMOTE_SUMMARY" || fail "Remote success did not report published_and_synced."

assert_fails env \
  GH_FIXTURE_DIR="$ARTIFACTS" GH_CASK_PATH="$CASK" CURL_APPCAST_PATH="${ARTIFACTS}/appcast.xml" \
  PATH="${TEST_DIR}/bin:${PATH}" "$VERIFY_SCRIPT" remote v1.2.3 ygsgdbd/TypeSwitch "$(printf '0%.0s' {1..64})"

BAD_LATEST="${TEST_DIR}/bad-latest.xml"
sed 's/<sparkle:shortVersionString>1.2.3/<sparkle:shortVersionString>1.2.2/' "${ARTIFACTS}/appcast.xml" > "$BAD_LATEST"
assert_fails env \
  GH_FIXTURE_DIR="$ARTIFACTS" GH_CASK_PATH="$CASK" CURL_APPCAST_PATH="$BAD_LATEST" \
  PATH="${TEST_DIR}/bin:${PATH}" "$VERIFY_SCRIPT" remote v1.2.3 ygsgdbd/TypeSwitch "$SHA"

BAD_CASK="${TEST_DIR}/bad-typeswitch.rb"
sed 's/version "1.2.3"/version "1.2.2"/' "$CASK" > "$BAD_CASK"
PENDING_SUMMARY="${TEST_DIR}/pending-summary.md"
if GITHUB_STEP_SUMMARY="$PENDING_SUMMARY" \
  GH_FIXTURE_DIR="$ARTIFACTS" GH_CASK_PATH="$BAD_CASK" CURL_APPCAST_PATH="${ARTIFACTS}/appcast.xml" \
  PATH="${TEST_DIR}/bin:${PATH}" "$VERIFY_SCRIPT" remote v1.2.3 ygsgdbd/TypeSwitch "$SHA" >/dev/null 2>&1; then
  fail "Outdated Homebrew cask unexpectedly passed verification."
fi
grep -q '`published_homebrew_pending`' "$PENDING_SUMMARY" || fail "Homebrew mismatch did not report published_homebrew_pending."

UPDATED_CASK="${TEST_DIR}/update-typeswitch.rb"
sed 's/version "1.2.3"/version "0.1.0"/' "$CASK" > "$UPDATED_CASK"
ruby "$CASK_SCRIPT" "$UPDATED_CASK" v1.2.3 "$SHA" >/dev/null
EXPECTED_CASK=$(cat "$UPDATED_CASK")
ruby "$CASK_SCRIPT" "$UPDATED_CASK" v1.2.3 "$SHA" >/dev/null
[[ "$(cat "$UPDATED_CASK")" == "$EXPECTED_CASK" ]] || fail "Cask updater is not idempotent."
assert_fails ruby "$CASK_SCRIPT" "$UPDATED_CASK" 1.2.3 "$SHA"
printf '  version "9.9.9"\n' >> "$UPDATED_CASK"
assert_fails ruby "$CASK_SCRIPT" "$UPDATED_CASK" v1.2.3 "$SHA"

WORKFLOW="${ROOT_DIR}/.github/workflows/release.yml"
PR_WORKFLOW="${ROOT_DIR}/.github/workflows/pr-checks.yml"
JUSTFILE="${ROOT_DIR}/justfile"
for job in publish sync_homebrew verify_distribution; do
  grep -q "^  ${job}:" "$WORKFLOW" || fail "Workflow is missing the ${job} job."
done
[[ "$(grep -Fc 'secrets.HOMEBREW_TAP_TOKEN' "$WORKFLOW")" == "1" ]] || fail "Homebrew token must be scoped only to the Homebrew sync checkout."
grep -Fq 'overwrite_files: true' "$WORKFLOW" || fail "GitHub Release asset upload must be retry-safe."
grep -Fq 'if: ${{ always() && needs.publish.result == '\''success'\'' }}' "$WORKFLOW" || fail "Distribution verification must run after publish when Homebrew sync fails."
grep -A4 '^  verify_distribution:' "$WORKFLOW" | grep -q 'runs-on: macos-26' || fail "Distribution verification must run on macOS."
grep -Fq 'script/verify_release.sh remote "$RELEASE_TAG" "$GITHUB_REPOSITORY" "$EXPECTED_SHA256"' "$WORKFLOW" || fail "Distribution verification must pass the publish SHA."

grep -q '^  release-scripts:$' "$PR_WORKFLOW" || fail "PR Checks must include an independent release-scripts job."
grep -A4 '^  release-scripts:$' "$PR_WORKFLOW" | grep -q 'runs-on: macos-26' || fail "PR release script tests must run on macOS."
grep -q '^test-release-scripts:$' "$JUSTFILE" || fail "justfile must expose test-release-scripts."
grep -Eq '^check: .*test-release-scripts' "$JUSTFILE" || fail "just check must include release script tests."

echo "Release script tests passed."
