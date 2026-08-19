#!/usr/bin/env bash

set -euo pipefail

if [[ "$#" -ne 2 ]]; then
  echo "Usage: script/ensure_release_absent.sh <repository> <tag>" >&2
  exit 1
fi

repository="$1"
tag="$2"
response_file=$(mktemp)
trap 'rm -f "$response_file"' EXIT

set +e
gh api --include --silent "repos/${repository}/releases/tags/${tag}" >"$response_file" 2>&1
gh_status=$?
set -e

http_status=$(awk '
  $1 ~ /^HTTP\// && $2 ~ /^[0-9][0-9][0-9]$/ { status = $2 }
  END { print status }
' "$response_file")

case "$http_status" in
  404)
    echo "No existing GitHub Release found for ${tag}."
    ;;
  200)
    echo "GitHub Release ${repository}@${tag} already exists; create a new SemVer tag instead." >&2
    exit 1
    ;;
  "")
    echo "Could not verify whether GitHub Release ${repository}@${tag} exists (gh exited ${gh_status})." >&2
    cat "$response_file" >&2
    exit 1
    ;;
  *)
    echo "Could not verify whether GitHub Release ${repository}@${tag} exists (HTTP ${http_status})." >&2
    cat "$response_file" >&2
    exit 1
    ;;
esac
