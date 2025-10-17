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

echo "==> Relocating binaries in: $BUNDLE_DIR" >&2
echo "" >&2

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

echo "==> Relocating binaries" >&2
BIN_COUNT=0
if [ -d "$BUNDLE_DIR/bin" ]; then
    find "$BUNDLE_DIR/bin" -type f 2>/dev/null | while read -r binary; do
        if file "$binary" | grep -q "Mach-O"; then
            BIN_COUNT=$((BIN_COUNT + 1))
            relocate_file "$binary" "@loader_path/../lib/"
        fi
    done
fi
echo "    Processed binaries" >&2
echo "" >&2

echo "==> Relocating libraries" >&2
LIB_COUNT=0
if [ -d "$BUNDLE_DIR/lib" ]; then
    find "$BUNDLE_DIR/lib" -name "*.dylib" -type f 2>/dev/null | while read -r dylib; do
        LIB_COUNT=$((LIB_COUNT + 1))
        lib_name=$(basename "$dylib")

        install_name_tool -id "@loader_path/$lib_name" "$dylib" 2>/dev/null || true

        relocate_file "$dylib" "@loader_path/"
    done
fi
echo "    Processed libraries" >&2
echo "" >&2

echo "==> Relocating library modules and subdirectory binaries" >&2
find "$BUNDLE_DIR/lib" -mindepth 2 -type f 2>/dev/null | while read -r module; do
    if file "$module" 2>/dev/null | grep -q "Mach-O"; then
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
done
echo "    Processed library modules and binaries" >&2
echo "" >&2

echo "==> Verification" >&2
VERIFY_TMP="/tmp/verify_placeholders_$$"
rm -f "$VERIFY_TMP"

find "$BUNDLE_DIR/bin" "$BUNDLE_DIR/lib" -type f 2>/dev/null | while read -r file; do
    if file "$file" 2>/dev/null | grep -q "Mach-O"; then
        if otool -L "$file" 2>/dev/null | grep -q -E "(@@HOMEBREW_PREFIX@@|@@HOMEBREW_CELLAR@@)"; then
            echo "    Warning: $file still has placeholders" >&2
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
echo "==> Summary:" >&2
echo "    Bundle: $BUNDLE_DIR" >&2
echo "    Relocation complete" >&2
echo "" >&2
