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
gh api --include --jq '.draft' "repos/${repository}/releases/tags/${tag}" >"$response_file" 2>&1
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
    release_draft=$(awk '
      $0 == "true" || $0 == "false" { value = $0 }
      END { print value }
    ' "$response_file")

    case "$release_draft" in
      true)
        echo "Draft GitHub Release ${repository}@${tag} already exists and may be left by an incomplete publish." >&2
        echo "Inspect it before recovery:" >&2
        echo "  gh release view ${tag} --repo ${repository} --json isDraft,url,assets" >&2
        echo "If isDraft is true, delete only that draft, then rerun only the failed jobs:" >&2
        echo "  gh release delete ${tag} --repo ${repository} --yes" >&2
        echo "Replace the example ID with the failed workflow run ID:" >&2
        echo "  FAILED_RUN_ID=123456789" >&2
        echo "  gh run rerun \"\$FAILED_RUN_ID\" --failed --repo ${repository}" >&2
        exit 1
        ;;
      false)
        echo "Published GitHub Release ${repository}@${tag} already exists and must not be rebuilt or overwritten; create a new SemVer tag instead." >&2
        exit 1
        ;;
      *)
        echo "Could not determine whether GitHub Release ${repository}@${tag} is a draft." >&2
        cat "$response_file" >&2
        exit 1
        ;;
    esac
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
