#!/bin/sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

cleanup() {
    if [ -n "${TEMP_DIR:-}" ] && [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
    fi
    rm -f "/tmp/dylibs_list_$$"
}
trap cleanup EXIT

if ! "$SCRIPT_DIR/create-portable-package.sh" nss > /dev/null 2>&1; then
    echo "Error: Failed to create NSS package" >&2
    exit 1
fi

ARCHIVE=$(find . -maxdepth 1 -name "nss-*.tar.gz" -type f | head -1)
[ -z "$ARCHIVE" ] && { echo "Error: NSS archive not found" >&2; exit 1; }

ARCHIVE=$(cd "$(dirname "$ARCHIVE")" && pwd)/$(basename "$ARCHIVE")
TEMP_DIR="/tmp/nss-build-$$"
mkdir -p "$TEMP_DIR"
tar -xzf "$ARCHIVE" -C "$TEMP_DIR"

EXTRACTED_DIR=$(find "$TEMP_DIR" -mindepth 1 -maxdepth 1 -type d -name "nss-*" | head -1)
[ -z "$EXTRACTED_DIR" ] && { echo "Error: Could not find extracted directory" >&2; exit 1; }

cd "$EXTRACTED_DIR"
[ ! -f "bin/certutil" ] && { echo "Error: certutil not found" >&2; exit 1; }

NEEDED_LIBS_FILE="/tmp/needed_libs_$$"
ANALYZED_FILE="/tmp/analyzed_$$"
QUEUE_FILE="/tmp/queue_$$"

: > "$NEEDED_LIBS_FILE"
: > "$ANALYZED_FILE"
echo "bin/certutil" > "$QUEUE_FILE"

while [ -s "$QUEUE_FILE" ]; do
    FILE=$(head -1 "$QUEUE_FILE")
    tail -n +2 "$QUEUE_FILE" > "${QUEUE_FILE}.tmp" && mv "${QUEUE_FILE}.tmp" "$QUEUE_FILE"

    BASENAME=$(basename "$FILE")
    if grep -Fxq "$BASENAME" "$ANALYZED_FILE" 2>/dev/null; then
        continue
    fi
    echo "$BASENAME" >> "$ANALYZED_FILE"

    DEPS=$(otool -L "$FILE" 2>/dev/null | grep -E "@executable_path/lib/|@loader_path" | awk '{print $1}' | sed 's|.*/||' || true)

    for DEP in $DEPS; do
        if ! grep -Fxq "$DEP" "$NEEDED_LIBS_FILE" 2>/dev/null; then
            echo "$DEP" >> "$NEEDED_LIBS_FILE"
        fi

        if [ -f "lib/$DEP" ]; then
            echo "lib/$DEP" >> "$QUEUE_FILE"
        fi
    done
done

find bin -type f ! -name "certutil" -delete 2>/dev/null || true

find lib -maxdepth 1 -name "*.dylib" -type f 2>/dev/null > "/tmp/dylibs_list_$$"
while IFS= read -r dylib; do
    DYLIB_NAME=$(basename "$dylib")
    grep -Fxq "$DYLIB_NAME" "$NEEDED_LIBS_FILE" 2>/dev/null || rm -f "$dylib"
done < "/tmp/dylibs_list_$$"

rm -f "$NEEDED_LIBS_FILE" "$ANALYZED_FILE" "$QUEUE_FILE"

ARCHIVE_DIR=$(dirname "$ARCHIVE")
ARCHIVE_BASE=$(basename "$ARCHIVE" .tar.gz)
MINIMAL_ARCHIVE="$ARCHIVE_DIR/${ARCHIVE_BASE}.tar.gz"

rm -f "$ARCHIVE"
tar -czf "$MINIMAL_ARCHIVE" -C "$EXTRACTED_DIR" .
