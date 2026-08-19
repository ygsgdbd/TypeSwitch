#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
VERIFY_SCRIPT="${ROOT_DIR}/script/verify_release.sh"
CASK_SCRIPT="${ROOT_DIR}/script/update_homebrew_cask.rb"
ORDER_SCRIPT="${ROOT_DIR}/script/validate_release_order.rb"
RELEASE_ABSENT_SCRIPT="${ROOT_DIR}/script/ensure_release_absent.sh"
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

assert_contains() {
  grep -Fq -- "$2" "$1" || fail "$1 is missing: $2"
}

assert_not_contains() {
  if grep -Fq -- "$2" "$1"; then
    fail "$1 must not contain: $2"
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
  local public_key="${FIXTURE_PUBLIC_KEY:-cHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHA=}"
  local signature="${FIXTURE_SIGNATURE-valid-test-signature}"
  local appcast_layout="${FIXTURE_APPCAST_LAYOUT:-child}"
  local staging="${TEST_DIR}/staging"
  local sha size appcast_url appcast_size version_elements enclosure_version_attributes

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
  <key>SUPublicEDKey</key><string>${public_key}</string>
</dict>
</plist>
EOF

  ditto -c -k --keepParent "${staging}/TypeSwitch.app" "${dir}/TypeSwitch-macOS-universal.zip"
  sha=$(sha256_file "${dir}/TypeSwitch-macOS-universal.zip")
  size=$(stat -f '%z' "${dir}/TypeSwitch-macOS-universal.zip")
  appcast_url="${FIXTURE_APPCAST_URL:-https://github.com/ygsgdbd/TypeSwitch/releases/download/${tag}/TypeSwitch-macOS-universal.zip}"
  appcast_size="${FIXTURE_APPCAST_SIZE:-$size}"
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
      <enclosure url="${appcast_url}" length="${appcast_size}" sparkle:edSignature="${signature}"${enclosure_version_attributes} />
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

cat > "${TEST_DIR}/bin/sign_update" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
legacy_key=$(cat)
expected_key=$(ruby -rbase64 -e 'STDOUT.write(Base64.strict_encode64(("\0" * 64) + ("p" * 32)))')
[[ "$legacy_key" == "$expected_key" ]] || exit 1
[[ "$1" == "--ed-key-file" && "$2" == "-" && "$3" == "--verify" ]] || exit 1
[[ -f "$4" && "$5" == "valid-test-signature" ]] || exit 1
EOF
chmod +x "${TEST_DIR}/bin/sign_update"
export SPARKLE_SIGN_UPDATE="${TEST_DIR}/bin/sign_update"

cat > "${TEST_DIR}/bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

[[ "$#" == 4 ]] || exit 99
[[ "$1" == "api" && "$2" == "--include" && "$3" == "--silent" ]] || exit 99
[[ "$4" == "repos/ygsgdbd/TypeSwitch/releases/tags/v1.2.3" ]] || exit 99

case "${GH_STUB_MODE:-}" in
  404)
    printf 'HTTP/2.0 404 Not Found\n\n'
    exit 1
    ;;
  200)
    printf 'HTTP/2.0 200 OK\n\n'
    ;;
  403)
    printf 'HTTP/2.0 403 Forbidden\n\n'
    exit 1
    ;;
  429)
    printf 'HTTP/2.0 429 Too Many Requests\n\n'
    exit 1
    ;;
  500)
    printf 'HTTP/2.0 500 Internal Server Error\n\n'
    exit 1
    ;;
  network)
    echo 'network unavailable' >&2
    exit 1
    ;;
  *)
    exit 98
    ;;
esac
EOF
chmod +x "${TEST_DIR}/bin/gh"

PATH="${TEST_DIR}/bin:${PATH}" GH_STUB_MODE=404 \
  "$RELEASE_ABSENT_SCRIPT" ygsgdbd/TypeSwitch v1.2.3 >/dev/null
for stub_mode in 200 403 429 500 network; do
  assert_fails env PATH="${TEST_DIR}/bin:${PATH}" GH_STUB_MODE="$stub_mode" \
    "$RELEASE_ABSENT_SCRIPT" ygsgdbd/TypeSwitch v1.2.3
done

ARTIFACTS="${TEST_DIR}/artifacts"
make_artifacts "$ARTIFACTS" v1.2.3
PATH="${TEST_DIR}/bin:${PATH}" "$VERIFY_SCRIPT" v1.2.3 "$ARTIFACTS" >/dev/null

FIXTURE_APPCAST_LAYOUT=attributes make_artifacts "$ARTIFACTS" v1.2.3
PATH="${TEST_DIR}/bin:${PATH}" "$VERIFY_SCRIPT" v1.2.3 "$ARTIFACTS" >/dev/null

assert_fails "$VERIFY_SCRIPT" 1.2.3 "$ARTIFACTS"
assert_fails "$VERIFY_SCRIPT" v01.2.3 "$ARTIFACTS"

printf '%s\n' v1.9.0 v1.10.0 v01.99.0 invalid | ruby "$ORDER_SCRIPT" v1.10.0 >/dev/null
if printf '%s\n' v1.9.0 v1.10.0 | ruby "$ORDER_SCRIPT" v1.9.0 >/dev/null 2>&1; then
  fail "Release order validation accepted a lower version."
fi
if printf '%s\n' v1.2.3 | ruby "$ORDER_SCRIPT" v01.2.3 >/dev/null 2>&1; then
  fail "Release order validation accepted a non-strict current tag."
fi

make_artifacts "$ARTIFACTS" v1.2.3
printf 'corruption\n' >> "${ARTIFACTS}/TypeSwitch-macOS-universal.zip"
assert_fails env PATH="${TEST_DIR}/bin:${PATH}" "$VERIFY_SCRIPT" v1.2.3 "$ARTIFACTS"

FIXTURE_PLIST_VERSION=1.2.4 make_artifacts "$ARTIFACTS" v1.2.3
assert_fails env PATH="${TEST_DIR}/bin:${PATH}" "$VERIFY_SCRIPT" v1.2.3 "$ARTIFACTS"
FIXTURE_BUILD= make_artifacts "$ARTIFACTS" v1.2.3
assert_fails env PATH="${TEST_DIR}/bin:${PATH}" "$VERIFY_SCRIPT" v1.2.3 "$ARTIFACTS"
FIXTURE_MINIMUM=13.0 make_artifacts "$ARTIFACTS" v1.2.3
assert_fails env PATH="${TEST_DIR}/bin:${PATH}" "$VERIFY_SCRIPT" v1.2.3 "$ARTIFACTS"
FIXTURE_FEED_URL=https://example.invalid/appcast.xml make_artifacts "$ARTIFACTS" v1.2.3
assert_fails env PATH="${TEST_DIR}/bin:${PATH}" "$VERIFY_SCRIPT" v1.2.3 "$ARTIFACTS"

make_artifacts "$ARTIFACTS" v1.2.3
assert_fails env PATH="${TEST_DIR}/bin:${PATH}" LIPO_ARCHS=arm64 "$VERIFY_SCRIPT" v1.2.3 "$ARTIFACTS"
FIXTURE_APPCAST_BUILD=wrong-build make_artifacts "$ARTIFACTS" v1.2.3
assert_fails env PATH="${TEST_DIR}/bin:${PATH}" "$VERIFY_SCRIPT" v1.2.3 "$ARTIFACTS"
FIXTURE_APPCAST_URL=https://example.invalid/TypeSwitch.zip make_artifacts "$ARTIFACTS" v1.2.3
assert_fails env PATH="${TEST_DIR}/bin:${PATH}" "$VERIFY_SCRIPT" v1.2.3 "$ARTIFACTS"
FIXTURE_APPCAST_SIZE=1 make_artifacts "$ARTIFACTS" v1.2.3
assert_fails env PATH="${TEST_DIR}/bin:${PATH}" "$VERIFY_SCRIPT" v1.2.3 "$ARTIFACTS"
FIXTURE_SIGNATURE= make_artifacts "$ARTIFACTS" v1.2.3
assert_fails env PATH="${TEST_DIR}/bin:${PATH}" "$VERIFY_SCRIPT" v1.2.3 "$ARTIFACTS"
FIXTURE_SIGNATURE=wrong-signature make_artifacts "$ARTIFACTS" v1.2.3
assert_fails env PATH="${TEST_DIR}/bin:${PATH}" "$VERIFY_SCRIPT" v1.2.3 "$ARTIFACTS"
FIXTURE_PUBLIC_KEY=eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHg= make_artifacts "$ARTIFACTS" v1.2.3
assert_fails env PATH="${TEST_DIR}/bin:${PATH}" "$VERIFY_SCRIPT" v1.2.3 "$ARTIFACTS"

make_artifacts "$ARTIFACTS" v1.2.3
CASK="${TEST_DIR}/typeswitch.rb"
SHA=$(sha256_file "${ARTIFACTS}/TypeSwitch-macOS-universal.zip")
cat > "$CASK" <<EOF
cask "typeswitch" do
  version "1.2.3"
  sha256 "$(printf '0%.0s' {1..64})"
  url "https://example.invalid/TypeSwitch.zip"
end
EOF

ruby "$CASK_SCRIPT" "$CASK" v1.2.4 "$SHA" >/dev/null
assert_contains "$CASK" '  version "1.2.4"'
assert_contains "$CASK" "  sha256 \"${SHA}\""
assert_contains "$CASK" '  url "https://github.com/ygsgdbd/TypeSwitch/releases/download/v1.2.4/TypeSwitch-macOS-universal.zip"'
EXPECTED_CASK=$(cat "$CASK")
ruby "$CASK_SCRIPT" "$CASK" v1.2.4 "$SHA" >/dev/null
[[ "$(cat "$CASK")" == "$EXPECTED_CASK" ]] || fail "Cask updater is not idempotent."
assert_fails ruby "$CASK_SCRIPT" "$CASK" v1.2.3 "$SHA"
[[ "$(cat "$CASK")" == "$EXPECTED_CASK" ]] || fail "Cask updater modified the file during a rejected downgrade."
assert_fails ruby "$CASK_SCRIPT" "$CASK" 1.2.3 "$SHA"
printf '  version "9.9.9"\n' >> "$CASK"
assert_fails ruby "$CASK_SCRIPT" "$CASK" v1.2.3 "$SHA"

WORKFLOW="${ROOT_DIR}/.github/workflows/release.yml"
PR_WORKFLOW="${ROOT_DIR}/.github/workflows/pr-checks.yml"
JUSTFILE="${ROOT_DIR}/justfile"

JOB_NAMES=$(awk '
  /^jobs:$/ { in_jobs = 1; next }
  in_jobs && /^[^ ]/ { in_jobs = 0 }
  in_jobs && /^  [a-zA-Z0-9_]+:$/ {
    name = $0
    sub(/^  /, "", name)
    sub(/:$/, "", name)
    print name
  }
' "$WORKFLOW")
[[ "$JOB_NAMES" == $'publish\nhomebrew' ]] || fail "Release workflow must contain only publish and homebrew jobs; got: $JOB_NAMES"

assert_contains "$WORKFLOW" 'group: release-${{ github.repository }}'
assert_contains "$WORKFLOW" 'queue: max'
assert_contains "$WORKFLOW" "git tag --merged origin/main --list 'v*'"
assert_contains "$WORKFLOW" 'ruby script/validate_release_order.rb "$RELEASE_TAG"'
assert_contains "$WORKFLOW" 'script/ensure_release_absent.sh "$GITHUB_REPOSITORY" "$RELEASE_TAG"'
assert_contains "$WORKFLOW" 'cp release-notes.md DerivedData/SparkleFeed/TypeSwitch-macOS-universal.md'
assert_contains "$WORKFLOW" '--embed-release-notes'
assert_contains "$WORKFLOW" 'script/verify_release.sh "$RELEASE_TAG" .'
assert_contains "$WORKFLOW" 'overwrite_files: false'
assert_not_contains "$WORKFLOW" 'workflow_dispatch'
assert_not_contains "$WORKFLOW" 'overwrite_files: true'
assert_not_contains "$WORKFLOW" 'generate_release_notes'
assert_not_contains "$WORKFLOW" 'verify_distribution'
assert_not_contains "$WORKFLOW" 'validate_release_version'
assert_not_contains "$WORKFLOW" 'name: Test release scripts'
assert_not_contains "$WORKFLOW" 'Validate Homebrew tap access'
assert_not_contains "$WORKFLOW" 'gh api markdown'
assert_not_contains "$WORKFLOW" 'release-notes.html'
[[ "$(grep -Fc 'secrets.HOMEBREW_TAP_TOKEN' "$WORKFLOW")" == "1" ]] || fail "Homebrew token must appear only in the tap checkout."
[[ ! -e "${ROOT_DIR}/script/validate_release_version.rb" ]] || fail "Obsolete release version helper still exists."

VALIDATE_TAG_LINE=$(grep -nF -- 'name: Validate release tag' "$WORKFLOW" | cut -d: -f1)
RELEASE_ABSENT_LINE=$(grep -nF -- 'name: Ensure GitHub Release does not already exist' "$WORKFLOW" | cut -d: -f1)
GENERATE_PROJECT_LINE=$(grep -nF -- 'name: Generate Xcode Project' "$WORKFLOW" | cut -d: -f1)
if (( VALIDATE_TAG_LINE >= RELEASE_ABSENT_LINE || RELEASE_ABSENT_LINE >= GENERATE_PROJECT_LINE )); then
  fail "GitHub Release absence check must run after tag validation and before project generation."
fi

assert_contains "$PR_WORKFLOW" 'release-scripts:'
assert_contains "$PR_WORKFLOW" 'run: script/test_release_scripts.sh'
assert_contains "$JUSTFILE" 'test-release-scripts:'

echo "Release script tests passed."
