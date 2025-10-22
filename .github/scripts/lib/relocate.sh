#!/bin/bash
# Relocate Mach-O binaries (dylibs, executables, bundles)
# This replicates what Homebrew does in fix_dynamic_linkage
#
# Usage: relocate_macho_files <prefix> <install_dir>
#   prefix: The hardcoded prefix path (e.g., /Users/Shared/Fadogen/postgresql/18)
#   install_dir: Where files are currently located (same as prefix when building direct)

set -e

relocate_macho_files() {
    local PREFIX="$1"
    local INSTALL_DIR="$2"

    echo "→ Relocating Mach-O files..."
    echo "  Prefix: ${PREFIX}"
    echo "  Install dir: ${INSTALL_DIR}"

    # Find ALL Mach-O files (executables, dylibs, bundles)
    # We check: bin/, sbin/, lib/, and any subdirectories
    local mach_o_files=()
    while IFS= read -r -d '' file; do
        # Skip symlinks
        [ -L "$file" ] && continue

        # Check if it's a Mach-O file
        if file "$file" | grep -q "Mach-O"; then
            mach_o_files+=("$file")
        fi
    done < <(find "$INSTALL_DIR" -type f \( -path "*/bin/*" -o -path "*/sbin/*" -o -path "*/lib/*" \) -print0 2>/dev/null)

    echo "  Found ${#mach_o_files[@]} Mach-O files"

    # Process each Mach-O file
    for file in "${mach_o_files[@]}"; do
        local file_type
        file_type=$(file "$file")

        # 1. Fix dylib ID if this is a dylib
        if echo "$file_type" | grep -q "dynamically linked shared library"; then
            local current_id
            current_id=$(otool -D "$file" 2>/dev/null | sed -n '2p')

            # Only fix if it's not already absolute or if it's wrong
            if [[ -n "$current_id" && "$current_id" != "$file" ]]; then
                # Calculate what the ID should be
                local relative_path="${file#"$INSTALL_DIR"}"
                local new_id="${PREFIX}${relative_path}"

                if [[ "$current_id" != "$new_id" ]]; then
                    echo "    Fixing dylib ID: $(basename "$file")"
                    echo "      Old: $current_id"
                    echo "      New: $new_id"
                    install_name_tool -id "$new_id" "$file" 2>/dev/null || {
                        echo "      WARNING: Failed to change ID, may need -headerpad_max_install_names at compile time"
                    }
                fi
            fi
        fi

        # 2. Fix all dynamically linked libraries references
        while IFS= read -r linked_lib; do
            # Skip system libraries
            [[ "$linked_lib" =~ ^/usr/lib/ ]] && continue
            [[ "$linked_lib" =~ ^/System/ ]] && continue

            # Skip if already pointing to correct absolute path
            [[ "$linked_lib" =~ ^${PREFIX}/ ]] && continue

            # This is a library we need to fix
            local lib_basename
            lib_basename=$(basename "$linked_lib")
            local new_path="${PREFIX}/lib/${lib_basename}"

            # Check if the library actually exists at the new location
            local check_path="${INSTALL_DIR}/lib/${lib_basename}"
            if [ -e "$check_path" ] || [ -L "$check_path" ]; then
                echo "    Fixing reference in $(basename "$file"): $lib_basename"
                echo "      Old: $linked_lib"
                echo "      New: $new_path"
                install_name_tool -change "$linked_lib" "$new_path" "$file" 2>/dev/null || {
                    echo "      WARNING: Failed to change install_name"
                }
            fi
        done < <(otool -L "$file" 2>/dev/null | tail -n +2 | awk '{print $1}' | grep -v ":")

        # 3. Fix rpaths if any (some packages use them)
        if otool -l "$file" 2>/dev/null | grep -q "LC_RPATH"; then
            while IFS= read -r rpath; do
                # Skip if already correct
                [[ "$rpath" =~ ^${PREFIX}/ ]] && continue

                # If rpath is relative or wrong, fix it
                if [[ "$rpath" =~ @loader_path|@executable_path ]] || [[ ! "$rpath" =~ ^/ ]]; then
                    local new_rpath="${PREFIX}/lib"
                    echo "    Fixing rpath in $(basename "$file")"
                    echo "      Old: $rpath"
                    echo "      New: $new_rpath"
                    # Try to delete old and add new
                    install_name_tool -delete_rpath "$rpath" "$file" 2>/dev/null || true
                    install_name_tool -add_rpath "$new_rpath" "$file" 2>/dev/null || true
                fi
            done < <(otool -l "$file" 2>/dev/null | grep -A 2 "LC_RPATH" | grep "path" | awk '{print $2}')
        fi
    done

    echo "✓ Relocation complete"
}
