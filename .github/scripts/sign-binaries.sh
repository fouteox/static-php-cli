#!/bin/sh
set -e

if [ -z "$1" ]; then
    echo "Usage: $0 <formula> [bundle_dir] [signing_identity]" >&2
    echo "" >&2
    echo "Example: $0 valkey" >&2
    echo "         $0 mariadb mariadb-portable 'Developer ID Application: Name (TEAMID)'" >&2
    exit 1
fi

FORMULA="$1"
BUNDLE_DIR="${2:-${FORMULA}-portable}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:?SIGNING_IDENTITY environment variable must be set}"

if [ ! -d "$BUNDLE_DIR" ]; then
    echo "Error: Bundle directory not found: $BUNDLE_DIR" >&2
    exit 1
fi

BUNDLE_DIR=$(cd "$BUNDLE_DIR" && pwd)

echo "==> Code Signing: $BUNDLE_DIR" >&2

sign_file() {
    file="$1"

    if ! file "$file" 2>/dev/null | grep -q "Mach-O"; then
        return 0
    fi

    codesign --force \
             --sign "$SIGNING_IDENTITY" \
             --timestamp \
             --options runtime \
             "$file" >/dev/null 2>&1 || {
        echo "    ⚠ Failed to sign: $(basename "$file")" >&2
        return 1
    }

    return 0
}

verify_signature() {
    file="$1"

    if ! file "$file" 2>/dev/null | grep -q "Mach-O"; then
        return 0
    fi

    if codesign --verify --strict "$file" 2>/dev/null; then
        return 0
    else
        echo "    ⚠ Verification failed: $file" >&2
        return 1
    fi
}

COUNTER_FILE="/tmp/sign_counter_$$"
VERIFY_FILE="/tmp/verify_counter_$$"
echo "0" > "$COUNTER_FILE"
echo "0" > "$VERIFY_FILE"

find "$BUNDLE_DIR/lib" -mindepth 2 -type f 2>/dev/null | while read -r module; do
    if sign_file "$module"; then
        count=$(cat "$COUNTER_FILE")
        echo "$((count + 1))" > "$COUNTER_FILE"
    fi
done

if [ -d "$BUNDLE_DIR/lib" ]; then
    find "$BUNDLE_DIR/lib" -maxdepth 1 -name "*.dylib" -type f 2>/dev/null | while read -r dylib; do
        if sign_file "$dylib"; then
            count=$(cat "$COUNTER_FILE")
            echo "$((count + 1))" > "$COUNTER_FILE"
        fi
    done
fi

if [ -d "$BUNDLE_DIR/bin" ]; then
    find "$BUNDLE_DIR/bin" -type f 2>/dev/null | while read -r binary; do
        if sign_file "$binary"; then
            count=$(cat "$COUNTER_FILE")
            echo "$((count + 1))" > "$COUNTER_FILE"
        fi
    done
fi

SIGNED_COUNT=$(cat "$COUNTER_FILE")
echo "    Total signed: $SIGNED_COUNT files" >&2
find "$BUNDLE_DIR/bin" "$BUNDLE_DIR/lib" -type f 2>/dev/null | while read -r file; do
    if ! verify_signature "$file"; then
        count=$(cat "$VERIFY_FILE")
        echo "$((count + 1))" > "$VERIFY_FILE"
    fi
done

VERIFY_FAILED=$(cat "$VERIFY_FILE")

if [ "$VERIFY_FAILED" -eq 0 ]; then
    echo "    ✓ All signatures verified successfully" >&2
else
    echo "    ⚠ $VERIFY_FAILED signatures failed verification" >&2
fi

rm -f "$COUNTER_FILE" "$VERIFY_FILE"
