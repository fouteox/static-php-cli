#!/bin/sh
set -e

if [ -z "$1" ]; then
    echo "Usage: $0 <formula> [bundle_dir]" >&2
    exit 1
fi

FORMULA="$1"
BUNDLE_DIR="${2:-${FORMULA}-portable}"

if [ ! -d "$BUNDLE_DIR" ]; then
    echo "Error: Bundle directory not found: $BUNDLE_DIR" >&2
    exit 1
fi

BUNDLE_DIR=$(cd "$BUNDLE_DIR" && pwd)

echo "==> Relocating binaries: $BUNDLE_DIR" >&2

relocate_file() {
    file="$1"
    base_path="$2"

    deps=$(otool -L "$file" 2>/dev/null | grep -E "(@@HOMEBREW_PREFIX@@|@@HOMEBREW_CELLAR@@)" || true)

    if [ -z "$deps" ]; then
        return
    fi

    echo "$deps" | while IFS= read -r line; do
        old_path=$(echo "$line" | awk '{print $1}')
        lib_name=$(basename "$old_path")
        new_path="${base_path}${lib_name}"

        install_name_tool -change "$old_path" "$new_path" "$file" 2>/dev/null || true
    done
}

# Use temp files for POSIX sh compatibility
BINARIES_TMP="/tmp/binaries_$$"
DYLIBS_TMP="/tmp/dylibs_$$"
MODULES_TMP="/tmp/modules_$$"

cleanup() {
    rm -f "$BINARIES_TMP" "$DYLIBS_TMP" "$MODULES_TMP"
}
trap cleanup EXIT

BIN_COUNT=0
if [ -d "$BUNDLE_DIR/bin" ]; then
    find "$BUNDLE_DIR/bin" -type f 2>/dev/null > "$BINARIES_TMP"
    while IFS= read -r binary; do
        if file "$binary" 2>/dev/null | grep -q "Mach-O"; then
            BIN_COUNT=$((BIN_COUNT + 1))
            relocate_file "$binary" "@loader_path/../lib/"
        fi
    done < "$BINARIES_TMP"
fi

LIB_COUNT=0
if [ -d "$BUNDLE_DIR/lib" ]; then
    find "$BUNDLE_DIR/lib" -name "*.dylib" -type f 2>/dev/null > "$DYLIBS_TMP"
    while IFS= read -r dylib; do
        LIB_COUNT=$((LIB_COUNT + 1))
        lib_name=$(basename "$dylib")

        install_name_tool -id "@loader_path/$lib_name" "$dylib" 2>/dev/null || true

        relocate_file "$dylib" "@loader_path/"
    done < "$DYLIBS_TMP"
fi

MODULE_COUNT=0
find "$BUNDLE_DIR/lib" -mindepth 2 -type f 2>/dev/null > "$MODULES_TMP"
while IFS= read -r module; do
    if file "$module" 2>/dev/null | grep -q "Mach-O"; then
        MODULE_COUNT=$((MODULE_COUNT + 1))
        module_name=$(basename "$module")

        # Set ID for libraries (.so, .dylib)
        case "$module_name" in
            *.so|*.dylib)
                install_name_tool -id "@loader_path/$module_name" "$module" 2>/dev/null || true
                ;;
        esac

        # Relocate dependencies (all Mach-O files)
        relocate_file "$module" "@loader_path/../"
    fi
done < "$MODULES_TMP"

echo "    Relocated $BIN_COUNT binaries, $LIB_COUNT libraries, $MODULE_COUNT modules" >&2
echo "" >&2

VERIFY_TMP="/tmp/verify_placeholders_$$"
rm -f "$VERIFY_TMP"

find "$BUNDLE_DIR/bin" "$BUNDLE_DIR/lib" -type f 2>/dev/null | while read -r file; do
    if file "$file" 2>/dev/null | grep -q "Mach-O"; then
        if otool -L "$file" 2>/dev/null | grep -q -E "(@@HOMEBREW_PREFIX@@|@@HOMEBREW_CELLAR@@)"; then
            echo "$file" >> "$VERIFY_TMP"
        fi
    fi
done

if [ ! -f "$VERIFY_TMP" ] || [ ! -s "$VERIFY_TMP" ]; then
    echo "    ✓ All placeholders replaced" >&2
else
    REMAINING=$(wc -l < "$VERIFY_TMP" | tr -d ' ')
    echo "    ⚠ $REMAINING files still have placeholders" >&2
fi

rm -f "$VERIFY_TMP"
echo "" >&2
