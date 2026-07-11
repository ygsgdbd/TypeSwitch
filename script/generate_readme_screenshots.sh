#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA_DIR="${TMPDIR:-/tmp}/TypeSwitchReadmeScreenshotsDerived"
APP_PATH="$DERIVED_DATA_DIR/Build/Products/Debug/TypeSwitch.app"
BINARY_PATH="$APP_PATH/Contents/MacOS/TypeSwitch"
RAW_DIR="$ROOT_DIR/Documentation/Screenshots/raw"
OUTPUT_DIR="$ROOT_DIR/Documentation/Screenshots"
MENU_WINDOWS_HELPER="${TMPDIR:-/tmp}/typeswitch-readme-menu-windows"
WINDOW_SNAPSHOT="${TMPDIR:-/tmp}/typeswitch-readme-window-snapshot"
APP_PID=""
CAPTURE_DIR=""
DISPLAY_ID=""
DISPLAY_LEFT=""
DISPLAY_TOP=""
DISPLAY_RIGHT=""
DISPLAY_BOTTOM=""
DISPLAY_SCALE=""
PADDING_PIXELS=""

cleanup() {
    if [[ -n "$APP_PID" ]] && kill -0 "$APP_PID" 2>/dev/null; then
        kill "$APP_PID" 2>/dev/null || true
        wait "$APP_PID" 2>/dev/null || true
    fi
    APP_PID=""
    if [[ -n "$CAPTURE_DIR" && -d "$CAPTURE_DIR" ]]; then
        rm -r "$CAPTURE_DIR"
    fi
    CAPTURE_DIR=""
}

fail() {
    print -u2 "error: $1"
    exit 1
}

trap cleanup EXIT INT TERM

[[ "$(uname -s)" == "Darwin" ]] || fail "README screenshots can only be generated on macOS."
command -v tuist >/dev/null || fail "tuist is required."
command -v xcodebuild >/dev/null || fail "xcodebuild is required."
command -v magick >/dev/null || fail "ImageMagick is required (brew install imagemagick)."
command -v rtk >/dev/null || fail "rtk is required."
command -v screencapture >/dev/null || fail "screencapture is unavailable."

if ! /usr/bin/swift -e 'import CoreGraphics; exit(CGPreflightScreenCaptureAccess() ? 0 : 1)'; then
    fail "Screen Recording permission is required for the terminal or Codex. Enable it in System Settings > Privacy & Security > Screen Recording."
fi

if ! /usr/bin/swift -e 'import ApplicationServices; exit(AXIsProcessTrusted() ? 0 : 1)'; then
    fail "Accessibility permission is required for the terminal or Codex. Enable it in System Settings > Privacy & Security > Accessibility."
fi

if pgrep -x TypeSwitch >/dev/null 2>&1; then
    fail "Quit all running TypeSwitch instances before generating screenshots."
fi

mkdir -p "$RAW_DIR"

print "Generating Xcode project..."
cd "$ROOT_DIR"
rtk tuist generate

print "Building README screenshot app..."
rtk xcodebuild build \
    -project TypeSwitch.xcodeproj \
    -scheme TypeSwitch \
    -configuration Debug \
    -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED_DATA_DIR" \
    -skipPackagePluginValidation \
    -skipMacroValidation \
    CODE_SIGN_IDENTITY='' \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO

[[ -x "$BINARY_PATH" ]] || fail "Built TypeSwitch executable was not found at $BINARY_PATH."

print "Building window bounds helper..."
/usr/bin/xcrun swiftc \
    "$ROOT_DIR/script/readme_menu_windows.swift" \
    -o "$MENU_WINDOWS_HELPER"

apply_display_info() {
    local display_info="$1"
    local display_fields=("${(@s:,:)display_info}")
    [[ ${#display_fields[@]} -eq 7 ]] || fail "Unable to determine the capture display."
    DISPLAY_ID="${display_fields[1]}"
    DISPLAY_LEFT="${display_fields[2]}"
    DISPLAY_TOP="${display_fields[3]}"
    DISPLAY_RIGHT=$((DISPLAY_LEFT + display_fields[4]))
    DISPLAY_BOTTOM=$((DISPLAY_TOP + display_fields[5]))
    DISPLAY_SCALE=$(((display_fields[6] + display_fields[4] / 2) / display_fields[4]))
    PADDING_PIXELS=$((12 * DISPLAY_SCALE))
    print "Using display $DISPLAY_ID (${display_fields[6]}x${display_fields[7]} pixels)."
}

apply_display_info "$($MENU_WINDOWS_HELPER display)"

wait_for_process() {
    local attempt
    for attempt in {1..100}; do
        APP_PID="$(pgrep -x TypeSwitch | head -n 1 || true)"
        [[ -n "$APP_PID" ]] && return 0
        sleep 0.1
    done
    fail "TypeSwitch did not launch."
}

wait_for_menu_item() {
    local attempt
    for attempt in {1..100}; do
        if /usr/bin/osascript - \
            "$APP_PID" "$DISPLAY_LEFT" "$DISPLAY_TOP" "$DISPLAY_RIGHT" "$DISPLAY_BOTTOM" \
            >/dev/null 2>&1 <<'APPLESCRIPT'
on run argv
    set targetPID to item 1 of argv as integer
    set displayLeft to item 2 of argv as integer
    set displayTop to item 3 of argv as integer
    set displayRight to item 4 of argv as integer
    set displayBottom to item 5 of argv as integer
    tell application "System Events"
        tell first application process whose unix id is targetPID
            repeat with candidateMenuBar in menu bars
                if exists menu bar item "TypeSwitch" of candidateMenuBar then
                    set candidateItem to menu bar item "TypeSwitch" of candidateMenuBar
                    set {itemX, itemY} to position of candidateItem
                    set {itemWidth, itemHeight} to size of candidateItem
                    set centerX to itemX + itemWidth / 2
                    set centerY to itemY + itemHeight / 2
                    if itemWidth > 0 and itemHeight > 0 ¬
                        and centerX ≥ displayLeft and centerX < displayRight ¬
                        and centerY ≥ displayTop and centerY < displayBottom then
                        return true
                    end if
                end if
            end repeat
            error "TypeSwitch menu bar item was not found on the selected display."
        end tell
    end tell
end run
APPLESCRIPT
        then
            return 0
        fi
        sleep 0.1
    done
    fail "TypeSwitch menu bar item did not appear."
}

menu_item_display_info() {
    local attempt
    local menu_point
    for attempt in {1..100}; do
        menu_point="$(/usr/bin/osascript - "$APP_PID" 2>/dev/null <<'APPLESCRIPT'
on run argv
    set targetPID to item 1 of argv as integer
    tell application "System Events"
        tell first application process whose unix id is targetPID
            repeat with candidateMenuBar in menu bars
                if exists menu bar item "TypeSwitch" of candidateMenuBar then
                    set candidateItem to menu bar item "TypeSwitch" of candidateMenuBar
                    set {itemX, itemY} to position of candidateItem
                    set {itemWidth, itemHeight} to size of candidateItem
                    if itemWidth > 0 and itemHeight > 0 then
                        return (itemX as text) & "," & (itemY as text)
                    end if
                end if
            end repeat
            error "A visible TypeSwitch menu bar item was not found."
        end tell
    end tell
end run
APPLESCRIPT
)" || true
        if [[ -n "$menu_point" ]]; then
            local point_fields=("${(@s:,:)menu_point}")
            if [[ ${#point_fields[@]} -eq 2 ]]; then
                "$MENU_WINDOWS_HELPER" point "${point_fields[1]}" "${point_fields[2]}"
                return 0
            fi
        fi
        sleep 0.1
    done
    fail "Unable to determine which display hosts the TypeSwitch menu bar item."
}

launch_variant() {
    local language="$1"
    local locale="$2"
    local appearance="$3"
    local interface_style="$4"
    /usr/bin/open -n "$APP_PATH" --args \
        --readme-demo \
        --readme-appearance "$appearance" \
        --readme-display-id "$DISPLAY_ID" \
        -AppleInterfaceStyle "$interface_style" \
        -AppleLanguages "($language)" \
        -AppleLocale "$locale"
    wait_for_process
}

open_root_menu() {
    /usr/bin/osascript - \
        "$APP_PID" "$DISPLAY_LEFT" "$DISPLAY_TOP" "$DISPLAY_RIGHT" "$DISPLAY_BOTTOM" <<'APPLESCRIPT'
on run argv
    set targetPID to item 1 of argv as integer
    set displayLeft to item 2 of argv as integer
    set displayTop to item 3 of argv as integer
    set displayRight to item 4 of argv as integer
    set displayBottom to item 5 of argv as integer
    tell application "System Events"
        tell first application process whose unix id is targetPID
            repeat with candidateMenuBar in menu bars
                if exists menu bar item "TypeSwitch" of candidateMenuBar then
                    set candidateItem to menu bar item "TypeSwitch" of candidateMenuBar
                    set {itemX, itemY} to position of candidateItem
                    set {itemWidth, itemHeight} to size of candidateItem
                    set centerX to itemX + itemWidth / 2
                    set centerY to itemY + itemHeight / 2
                    if itemWidth > 0 and itemHeight > 0 ¬
                        and centerX ≥ displayLeft and centerX < displayRight ¬
                        and centerY ≥ displayTop and centerY < displayBottom then
                        click candidateItem
                        return
                    end if
                end if
            end repeat
            error "TypeSwitch menu bar item was not found on the selected display."
        end tell
    end tell
end run
APPLESCRIPT
    sleep 0.5
}

open_strategy_menu() {
    /usr/bin/osascript - \
        "$APP_PID" "$DISPLAY_LEFT" "$DISPLAY_TOP" "$DISPLAY_RIGHT" "$DISPLAY_BOTTOM" <<'APPLESCRIPT'
on run argv
    set targetPID to item 1 of argv as integer
    set displayLeft to item 2 of argv as integer
    set displayTop to item 3 of argv as integer
    set displayRight to item 4 of argv as integer
    set displayBottom to item 5 of argv as integer
    tell application "System Events"
        tell first application process whose unix id is targetPID
            repeat with candidateMenuBar in menu bars
                if exists menu bar item "TypeSwitch" of candidateMenuBar then
                    set candidateItem to menu bar item "TypeSwitch" of candidateMenuBar
                    set {itemX, itemY} to position of candidateItem
                    set {itemWidth, itemHeight} to size of candidateItem
                    set centerX to itemX + itemWidth / 2
                    set centerY to itemY + itemHeight / 2
                    if itemWidth > 0 and itemHeight > 0 ¬
                        and centerX ≥ displayLeft and centerX < displayRight ¬
                        and centerY ≥ displayTop and centerY < displayBottom then
                        tell menu item "Safari" of menu 1 of candidateItem
                            perform action "AXPress"
                        end tell
                        return
                    end if
                end if
            end repeat
            error "TypeSwitch menu bar item was not found on the selected display."
        end tell
    end tell
end run
APPLESCRIPT
    sleep 0.5
}

close_menu() {
    /usr/bin/osascript -e 'tell application "System Events" to key code 53'
    sleep 0.2
}

capture_visible_menus() {
    local output_path="$1"
    local background="$2"
    local attempt
    local window_list

    for attempt in {1..20}; do
        if window_list="$($MENU_WINDOWS_HELPER windows "$WINDOW_SNAPSHOT" "$DISPLAY_ID" "$APP_PID" 2>/dev/null)"; then
            break
        fi
        sleep 0.1
    done
    [[ -n "${window_list:-}" ]] || fail "Visible menu windows did not appear."

    CAPTURE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/typeswitch-readme-window-captures.XXXXXX")"
    local -a capture_paths capture_x capture_y capture_width capture_height
    local -a content_mask_paths content_mask_x content_mask_y
    local row
    local index=0
    local min_x min_y max_x max_y
    local content_min_x content_min_y content_max_x content_max_y
    local point_min_x point_min_y point_max_x point_max_y

    for row in "${(@f)window_list}"; do
        local fields=("${(@s:,:)row}")
        [[ ${#fields[@]} -eq 9 ]] || fail "Invalid menu window description: $row"

        local window_id="${fields[1]}"
        local content_x="${fields[2]}"
        local content_y="${fields[3]}"
        local content_width="${fields[4]}"
        local content_height="${fields[5]}"
        local point_x="${fields[6]}"
        local point_y="${fields[7]}"
        local point_width="${fields[8]}"
        local point_height="${fields[9]}"
        local raw_path="$CAPTURE_DIR/${index}-raw.png"
        local trimmed_path="$CAPTURE_DIR/${index}.png"

        /usr/sbin/screencapture -x -a -l"$window_id" "$raw_path"
        [[ -s "$raw_path" ]] || fail "Unable to capture menu window $window_id."
        local alpha_bounds=(
            "${(@s:,:)$(magick "$raw_path" -alpha extract -threshold 2% -trim -format '%w,%h,%X,%Y' info:)}"
        )
        [[ ${#alpha_bounds[@]} -eq 4 ]] || fail "Unable to measure menu window shadow $window_id."
        local opaque_bounds=(
            "${(@s:,:)$(magick "$raw_path" -alpha extract -threshold 99% -trim -format '%w,%h,%X,%Y' info:)}"
        )
        [[ ${#opaque_bounds[@]} -eq 4 \
            && "${opaque_bounds[1]}" -eq "$content_width" \
            && "${opaque_bounds[2]}" -eq "$content_height" ]] \
            || fail "Unable to locate menu window content $window_id."
        local content_mask_path="$CAPTURE_DIR/${index}-content-mask.png"
        local opaque_x="${opaque_bounds[3]#+}"
        local opaque_y="${opaque_bounds[4]#+}"
        magick \
            "$raw_path" \
            -alpha extract \
            +profile icc \
            -crop "${content_width}x${content_height}+${opaque_x}+${opaque_y}" \
            +repage \
            "$content_mask_path"
        local crop_geometry="${alpha_bounds[1]}x${alpha_bounds[2]}${alpha_bounds[3]}${alpha_bounds[4]}"
        magick "$raw_path" -crop "$crop_geometry" +repage "$trimmed_path"

        local dimensions=("${(@s:x:)$(magick identify -format '%wx%h' "$trimmed_path")}")
        local image_width="${dimensions[1]}"
        local image_height="${dimensions[2]}"
        local content_offset_x=$((${opaque_bounds[3]#+} - ${alpha_bounds[3]#+}))
        local content_offset_y=$((${opaque_bounds[4]#+} - ${alpha_bounds[4]#+}))
        local image_x=$((content_x - content_offset_x))
        local image_y=$((content_y - content_offset_y))

        capture_paths+=("$trimmed_path")
        capture_x+=("$image_x")
        capture_y+=("$image_y")
        capture_width+=("$image_width")
        capture_height+=("$image_height")
        content_mask_paths+=("$content_mask_path")
        content_mask_x+=("$content_x")
        content_mask_y+=("$content_y")

        if (( index == 0 )); then
            min_x=$image_x
            min_y=$image_y
            max_x=$((image_x + image_width))
            max_y=$((image_y + image_height))
            content_min_x=$content_x
            content_min_y=$content_y
            content_max_x=$((content_x + content_width))
            content_max_y=$((content_y + content_height))
            point_min_x=$point_x
            point_min_y=$point_y
            point_max_x=$((point_x + point_width))
            point_max_y=$((point_y + point_height))
        else
            (( image_x < min_x )) && min_x=$image_x
            (( image_y < min_y )) && min_y=$image_y
            (( image_x + image_width > max_x )) && max_x=$((image_x + image_width))
            (( image_y + image_height > max_y )) && max_y=$((image_y + image_height))
            (( content_x < content_min_x )) && content_min_x=$content_x
            (( content_y < content_min_y )) && content_min_y=$content_y
            (( content_x + content_width > content_max_x )) && content_max_x=$((content_x + content_width))
            (( content_y + content_height > content_max_y )) && content_max_y=$((content_y + content_height))
            (( point_x < point_min_x )) && point_min_x=$point_x
            (( point_y < point_min_y )) && point_min_y=$point_y
            (( point_x + point_width > point_max_x )) && point_max_x=$((point_x + point_width))
            (( point_y + point_height > point_max_y )) && point_max_y=$((point_y + point_height))
        fi
        (( index += 1 ))
    done

    local canvas_width=$((max_x - min_x + 2 * PADDING_PIXELS))
    local canvas_height=$((max_y - min_y + 2 * PADDING_PIXELS))
    local -a composite_command
    composite_command=(magick -size "${canvas_width}x${canvas_height}" "xc:$background")
    local capture_index
    for ((capture_index = 1; capture_index <= ${#capture_paths[@]}; capture_index++)); do
        local offset_x=$((capture_x[capture_index] - min_x + PADDING_PIXELS))
        local offset_y=$((capture_y[capture_index] - min_y + PADDING_PIXELS))
        composite_command+=(
            "${capture_paths[capture_index]}"
            -geometry "+${offset_x}+${offset_y}"
            -composite
        )
    done
    composite_command+=("$output_path")
    "${composite_command[@]}"

    local content_capture="$CAPTURE_DIR/content.png"
    "$MENU_WINDOWS_HELPER" content \
        "$APP_PID" \
        "$DISPLAY_ID" \
        "$point_min_x" \
        "$point_min_y" \
        "$((point_max_x - point_min_x))" \
        "$((point_max_y - point_min_y))" \
        "$((content_max_x - content_min_x))" \
        "$((content_max_y - content_min_y))" \
        "$content_capture"
    [[ -s "$content_capture" ]] || fail "Unable to capture rendered menu content."
    local content_dimensions=("${(@s:x:)$(magick identify -format '%wx%h' "$content_capture")}")
    local expected_content_width=$((content_max_x - content_min_x))
    local expected_content_height=$((content_max_y - content_min_y))
    [[ "${content_dimensions[1]}" -eq "$expected_content_width" \
        && "${content_dimensions[2]}" -eq "$expected_content_height" ]] \
        || fail "Rendered menu content has an unexpected scale."

    local content_mask="$CAPTURE_DIR/content-mask.png"
    local -a content_mask_command
    content_mask_command=(
        magick
        -size "${expected_content_width}x${expected_content_height}"
        xc:black
    )
    local mask_index
    for ((mask_index = 1; mask_index <= ${#content_mask_paths[@]}; mask_index++)); do
        local mask_offset_x=$((content_mask_x[mask_index] - content_min_x))
        local mask_offset_y=$((content_mask_y[mask_index] - content_min_y))
        content_mask_command+=(
            "${content_mask_paths[mask_index]}"
            -geometry "+${mask_offset_x}+${mask_offset_y}"
            -compose Lighten
            -composite
        )
    done
    content_mask_command+=("$content_mask")
    "${content_mask_command[@]}"

    local masked_content="$CAPTURE_DIR/masked-content.png"
    magick \
        "$content_capture" \
        "$content_mask" \
        -alpha off \
        -compose CopyOpacity \
        -composite \
        "$masked_content"

    local hybrid_path="$CAPTURE_DIR/hybrid.png"
    local content_offset_x=$((content_min_x - min_x + PADDING_PIXELS))
    local content_offset_y=$((content_min_y - min_y + PADDING_PIXELS))
    magick \
        "$output_path" \
        "$masked_content" \
        -geometry "+${content_offset_x}+${content_offset_y}" \
        -compose Over \
        -composite \
        "$hybrid_path"
    mv "$hybrid_path" "$output_path"

    local output_dimensions=("${(@s:x:)$(magick identify -format '%wx%h' "$output_path")}")
    local visible_bounds=(
        "${(@s:,:)$(magick "$output_path" -background "$background" -fuzz 2% -trim -format '%w,%h,%X,%Y' info:)}"
    )
    [[ ${#visible_bounds[@]} -eq 4 ]] || fail "Unable to measure composed menu shadows."
    local visible_left="${visible_bounds[3]#+}"
    local visible_top="${visible_bounds[4]#+}"
    local visible_right=$((output_dimensions[1] - visible_bounds[1] - visible_left))
    local visible_bottom=$((output_dimensions[2] - visible_bounds[2] - visible_top))
    local balanced_margin=$visible_left
    (( visible_top > balanced_margin )) && balanced_margin=$visible_top
    (( visible_right > balanced_margin )) && balanced_margin=$visible_right
    (( visible_bottom > balanced_margin )) && balanced_margin=$visible_bottom

    local balance_left=$((balanced_margin - visible_left))
    local balance_top=$((balanced_margin - visible_top))
    local balance_right=$((balanced_margin - visible_right))
    local balance_bottom=$((balanced_margin - visible_bottom))
    if (( balance_left + balance_top + balance_right + balance_bottom > 0 )); then
        local balanced_path="$CAPTURE_DIR/balanced.png"
        local balanced_width=$((output_dimensions[1] + balance_left + balance_right))
        local balanced_height=$((output_dimensions[2] + balance_top + balance_bottom))
        magick \
            -size "${balanced_width}x${balanced_height}" \
            "xc:$background" \
            "$output_path" \
            -geometry "+${balance_left}+${balance_top}" \
            -composite \
            "$balanced_path"
        mv "$balanced_path" "$output_path"
    fi

    local density_path="$CAPTURE_DIR/density.png"
    magick \
        "$output_path" \
        -units PixelsPerInch \
        -density "$((72 * DISPLAY_SCALE))" \
        "$density_path"
    mv "$density_path" "$output_path"

    rm -r "$CAPTURE_DIR"
    CAPTURE_DIR=""
    [[ -s "$output_path" ]] || fail "Screenshot was not written to $output_path."
}

capture_variant() {
    local language="$1"
    local locale="$2"
    local appearance="$3"
    local name="$4"
    local interface_style="Light"
    local background="#f0f2f7"
    local main_path="$RAW_DIR/${name}-main.png"
    local strategy_path="$RAW_DIR/${name}-strategy.png"

    if [[ "$appearance" == "dark" ]]; then
        interface_style="Dark"
        background="#141417"
    fi

    print "Capturing $name..."
    launch_variant "$language" "$locale" "$appearance" "$interface_style"
    local actual_display_info="$(menu_item_display_info)"
    local actual_display_fields=("${(@s:,:)actual_display_info}")
    if [[ "${actual_display_fields[1]}" != "$DISPLAY_ID" ]]; then
        cleanup
        apply_display_info "$actual_display_info"
        launch_variant "$language" "$locale" "$appearance" "$interface_style"
    fi
    wait_for_menu_item

    "$MENU_WINDOWS_HELPER" snapshot > "$WINDOW_SNAPSHOT"
    open_root_menu
    capture_visible_menus "$main_path" "$background"

    open_strategy_menu
    capture_visible_menus "$strategy_path" "$background"
    close_menu

    cleanup
    sleep 0.4
}

capture_variant en en_US light en-light
capture_variant en en_US dark en-dark
capture_variant zh-Hans zh_CN light zh-Hans-light
capture_variant zh-Hans zh_CN dark zh-Hans-dark

for name in en-light en-dark zh-Hans-light zh-Hans-dark; do
    background="#f0f2f7"
    if [[ "$name" == *-dark ]]; then
        background="#141417"
    fi
    magick \
        "$RAW_DIR/${name}-main.png" \
        "$RAW_DIR/${name}-strategy.png" \
        -background "$background" \
        -alpha remove \
        -alpha off \
        -gravity north \
        +smush 24 \
        "$OUTPUT_DIR/${name}.png"
done

expected_files=(
    "$RAW_DIR/en-light-main.png"
    "$RAW_DIR/en-light-strategy.png"
    "$RAW_DIR/en-dark-main.png"
    "$RAW_DIR/en-dark-strategy.png"
    "$RAW_DIR/zh-Hans-light-main.png"
    "$RAW_DIR/zh-Hans-light-strategy.png"
    "$RAW_DIR/zh-Hans-dark-main.png"
    "$RAW_DIR/zh-Hans-dark-strategy.png"
    "$OUTPUT_DIR/en-light.png"
    "$OUTPUT_DIR/en-dark.png"
    "$OUTPUT_DIR/zh-Hans-light.png"
    "$OUTPUT_DIR/zh-Hans-dark.png"
)

for path in "${expected_files[@]}"; do
    [[ -s "$path" ]] || fail "Expected screenshot is missing: $path"
done

print "Generated 8 raw screenshots and 4 README composites in $OUTPUT_DIR."
