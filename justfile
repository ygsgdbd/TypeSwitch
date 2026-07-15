default:
    @just --list

# Validate local tools and enable the repository-managed Git hook.
setup: check-swiftformat check-tuist
    git config core.hooksPath .githooks
    @echo "Git hooks enabled from .githooks."

# Format all managed Swift files.
format: check-swiftformat
    swiftformat --cache ignore .

# Format staged Swift files and stop the commit so changes can be reviewed.
format-staged: check-swiftformat
    #!/usr/bin/env bash
    set -euo pipefail

    repo_root="$(git rev-parse --show-toplevel)"
    cd "$repo_root"

    files=()
    while IFS= read -r -d '' file; do
        files+=("$file")
    done < <(git diff --cached --name-only --diff-filter=ACMR -z -- '*.swift')

    if [[ ${#files[@]} -eq 0 ]]; then
        exit 0
    fi

    temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/typeswitch-swiftformat.XXXXXX")"
    trap 'rm -rf "$temp_dir"' EXIT

    original_files=()
    formatted_files=()
    for file in "${files[@]}"; do
        original="$temp_dir/original/$file"
        formatted="$temp_dir/formatted/$file"
        mkdir -p "$(dirname "$original")" "$(dirname "$formatted")"
        git show ":$file" > "$original"
        cp "$original" "$formatted"
        original_files+=("$original")
        formatted_files+=("$formatted")
    done

    swiftformat --cache ignore --config "$repo_root/.swiftformat" "${formatted_files[@]}" >/dev/null

    needs_formatting_files=()
    for index in "${!files[@]}"; do
        if ! cmp -s "${original_files[$index]}" "${formatted_files[$index]}"; then
            needs_formatting_files+=("${files[$index]}")
        fi
    done

    if [[ ${#needs_formatting_files[@]} -eq 0 ]]; then
        exit 0
    fi

    partially_staged_files=()
    for file in "${needs_formatting_files[@]}"; do
        if ! git diff --quiet -- "$file"; then
            partially_staged_files+=("$file")
        fi
    done

    if [[ ${#partially_staged_files[@]} -gt 0 ]]; then
        echo "SwiftFormat cannot safely update partially staged Swift files:" >&2
        printf '  %s\n' "${partially_staged_files[@]}" >&2
        echo "Stage or stash the remaining edits, or run just format manually, then retry." >&2
        exit 1
    fi

    swiftformat --cache ignore "${needs_formatting_files[@]}"
    echo >&2
    echo "SwiftFormat updated staged Swift files in the working tree." >&2
    echo "Review the changes, run git add again, then retry the commit." >&2
    exit 1

# Check formatting without changing files.
lint: check-swiftformat
    swiftformat --cache ignore --lint .

# Check formatting with annotations suitable for GitHub Actions.
lint-ci: check-swiftformat
    swiftformat --cache ignore --lint . --reporter github-actions-log

# Generate the Tuist project and run the complete XCTest suite.
test: check-tuist
    tuist generate --no-open
    xcodebuild test \
        -project TypeSwitch.xcodeproj \
        -scheme TypeSwitch \
        -destination 'platform=macOS' \
        -testLanguage zh-Hans \
        -skipPackagePluginValidation \
        -skipMacroValidation \
        CODE_SIGN_IDENTITY='' \
        CODE_SIGNING_ALLOWED=NO \
        CODE_SIGNING_REQUIRED=NO

# Run the same formatting and test checks required by pull requests.
check: lint test

[private]
check-swiftformat:
    #!/usr/bin/env bash
    set -euo pipefail

    required="$(tr -d '[:space:]' < .swiftformat-version)"
    release_url="https://github.com/nicklockwood/SwiftFormat/releases/tag/$required"

    if ! command -v swiftformat >/dev/null 2>&1; then
        echo "SwiftFormat is required but is not installed." >&2
        echo "Install it manually with: brew install swiftformat" >&2
        echo "Required version: $required" >&2
        echo "Release: $release_url" >&2
        exit 1
    fi

    installed="$(swiftformat --version | tr -d '[:space:]')"
    if [[ "$installed" != "$required" ]]; then
        echo "SwiftFormat version mismatch." >&2
        echo "Required:  $required" >&2
        echo "Installed: $installed" >&2
        echo "Install the matching release manually: $release_url" >&2
        exit 1
    fi

[private]
check-tuist:
    #!/usr/bin/env bash
    set -euo pipefail

    if ! command -v tuist >/dev/null 2>&1; then
        echo "Tuist is required but is not installed." >&2
        echo "Install it manually with: brew install tuist" >&2
        exit 1
    fi
