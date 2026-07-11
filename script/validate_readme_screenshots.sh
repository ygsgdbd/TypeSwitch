#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RAW_DIR="$ROOT_DIR/Documentation/Screenshots/raw"

fail() {
    print -u2 "error: $1"
    exit 1
}

command -v magick >/dev/null || fail "ImageMagick is required."

screenshots=(
    en-light-main.png
    en-light-strategy.png
    en-dark-main.png
    en-dark-strategy.png
    zh-Hans-light-main.png
    zh-Hans-light-strategy.png
    zh-Hans-dark-main.png
    zh-Hans-dark-strategy.png
)

for name in "${screenshots[@]}"; do
    image_path="$RAW_DIR/$name"
    [[ -s "$image_path" ]] || fail "Missing screenshot: $image_path"

    background="#f0f2f7"
    if [[ "$name" == *-dark-* ]]; then
        background="#141417"
    fi

    dimensions=("${(@s:x:)$(magick identify -format '%wx%h' "$image_path")}")
    density_info=("${(@s:,:)$(magick identify -format '%x,%U' "$image_path")}")
    [[ ${#density_info[@]} -eq 2 ]] || fail "$name is missing screenshot scale metadata."
    case "${density_info[2]}" in
        PixelsPerInch)
            density="$(printf '%.0f' "${density_info[1]}")"
            ;;
        PixelsPerCentimeter)
            density="$(awk -v value="${density_info[1]}" 'BEGIN { printf "%.0f", value * 2.54 }')"
            ;;
        *)
            fail "$name has unsupported screenshot scale units: ${density_info[2]}"
            ;;
    esac
    expected_padding=$((12 * density / 72))
    measurement=("${(@s:,:)$(magick "$image_path" -background "$background" -fuzz 2% -trim -format '%w,%h,%X,%Y' info:)}")
    [[ ${#measurement[@]} -eq 4 ]] || fail "Unable to measure screenshot margins: $name"

    content_width="${measurement[1]}"
    content_height="${measurement[2]}"
    left="${measurement[3]#+}"
    top="${measurement[4]#+}"
    right=$((dimensions[1] - content_width - left))
    bottom=$((dimensions[2] - content_height - top))
    margins=($left $top $right $bottom)
    minimum=${margins[1]}
    maximum=${margins[1]}
    for margin in "${margins[@]}"; do
        (( margin < minimum )) && minimum=$margin
        (( margin > maximum )) && maximum=$margin
    done

    (( minimum >= expected_padding )) \
        || fail "$name has a clipped shadow or insufficient spacing: left=$left top=$top right=$right bottom=$bottom"
    (( maximum - minimum <= 2 )) \
        || fail "$name has uneven spacing: left=$left top=$top right=$right bottom=$bottom"

    if [[ "$name" == *-light-* ]]; then
        is_too_dark="$(magick "$image_path" -colorspace gray -format '%[fx:median<0.9?1:0]' info:)"
        [[ "$is_too_dark" == "0" ]] \
            || fail "$name has an unexpectedly gray light appearance."
    fi
done

print "Validated complete shadows and even outer spacing for ${#screenshots[@]} raw screenshots."

