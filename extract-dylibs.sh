#!/bin/sh
set -e

if [ -z "$1" ]; then
    echo "Usage: $0 <formula> [bottles_file] [output_dir]" >&2
    exit 1
fi

FORMULA="$1"
BOTTLES_FILE="${2:-/tmp/${FORMULA}_bottle_paths.txt}"
OUTPUT_DIR="${3:-${FORMULA}-portable}"
TEMP_DIR="/tmp/brew_extract_$$"

if [ ! -f "$BOTTLES_FILE" ]; then
    echo "Error: Bottles file not found: $BOTTLES_FILE" >&2
    exit 1
fi

cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

rm -rf "$OUTPUT_DIR" "$TEMP_DIR"
mkdir -p "$OUTPUT_DIR" "$TEMP_DIR"

OUTPUT_DIR=$(cd "$OUTPUT_DIR" && pwd)

echo "==> Extracting bottles for: $FORMULA" >&2
echo "" >&2

MAIN_BOTTLE=$(head -1 "$BOTTLES_FILE")

echo "==> Extracting main formula: $FORMULA" >&2
cd "$TEMP_DIR"
tar -xzf "$MAIN_BOTTLE"

EXTRACTED=$(find . -maxdepth 2 -type d -name "[0-9]*" | head -1)
if [ -z "$EXTRACTED" ]; then
    echo "Error: Could not find extracted directory" >&2
    exit 1
fi

EXTRACTED_PATH="$TEMP_DIR/$EXTRACTED"
echo "    Found: $EXTRACTED_PATH" >&2

cd "$OLDPWD"
# Copy all files including hidden ones (like .bottle/)
(cd "$EXTRACTED_PATH" && cp -a . "$OUTPUT_DIR/")

# Move .bottle/ contents to root for easier access
if [ -d "$OUTPUT_DIR/.bottle" ]; then
    (cd "$OUTPUT_DIR/.bottle" && cp -a . "$OUTPUT_DIR/") 2>/dev/null || true
    rm -rf "$OUTPUT_DIR/.bottle"
    echo "    Moved .bottle/ contents to root" >&2
fi

echo "    Copied to: $OUTPUT_DIR/" >&2
echo "" >&2

DEP_COUNT=$(tail -n +2 "$BOTTLES_FILE" | wc -l | tr -d ' ')
echo "==> Extracting $DEP_COUNT dependencies" >&2
echo "" >&2

CURRENT=0
tail -n +2 "$BOTTLES_FILE" | while IFS= read -r bottle; do
    [ -z "$bottle" ] && continue
    CURRENT=$((CURRENT + 1))

    BOTTLE_NAME=$(basename "$bottle" | cut -d'-' -f3)
    echo "[$CURRENT/$DEP_COUNT] Extracting: $BOTTLE_NAME" >&2

    rm -rf "${TEMP_DIR:?}"/*
    cd "$TEMP_DIR"
    tar -xzf "$bottle"

    EXTRACTED=$(find . -maxdepth 2 -type d -name "[0-9]*" -o -name "2[0-9][0-9][0-9]-*" | head -1)
    if [ -z "$EXTRACTED" ]; then
        echo "    Warning: Could not find extracted directory" >&2
        continue
    fi

    EXTRACTED_PATH="$TEMP_DIR/$EXTRACTED"

    if [ -d "$EXTRACTED_PATH/lib" ]; then
        mkdir -p "$OUTPUT_DIR/lib"

        find "$EXTRACTED_PATH/lib" -maxdepth 1 \( -name "*.dylib" -o -type l \) 2>/dev/null | while read -r dylib; do
            cp -a "$dylib" "$OUTPUT_DIR/lib/" 2>/dev/null || true
        done

        find "$EXTRACTED_PATH/lib" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | while read -r subdir; do
            if find "$subdir" -type f \( -name "*.dylib" -o -name "*.so" \) 2>/dev/null | grep -q .; then
                subdir_name=$(basename "$subdir")
                if [ ! -d "$OUTPUT_DIR/lib/$subdir_name" ]; then
                    cp -a "$subdir" "$OUTPUT_DIR/lib/" 2>/dev/null || true
                    echo "    Copied module directory: $subdir_name/" >&2
                fi
            fi
        done

        echo "    Copied dylibs to: $OUTPUT_DIR/lib/" >&2
    else
        echo "    Warning: No lib directory found" >&2
    fi

    if [ -d "$EXTRACTED_PATH/share" ]; then
        mkdir -p "$OUTPUT_DIR/share"
        cp -a "$EXTRACTED_PATH/share/"* "$OUTPUT_DIR/share/" 2>/dev/null || true
        echo "    Copied share resources" >&2
    fi

    cd "$OLDPWD"
done

echo "" >&2
echo "==> Summary:" >&2
echo "    Output directory: $OUTPUT_DIR/" >&2
BIN_COUNT=$(find "$OUTPUT_DIR/bin" -type f 2>/dev/null | wc -l | tr -d ' ')
LIB_COUNT=$(find "$OUTPUT_DIR/lib" -name "*.dylib" 2>/dev/null | wc -l | tr -d ' ')
echo "    Binaries: $BIN_COUNT" >&2
echo "    Libraries: $LIB_COUNT" >&2
echo "" >&2
