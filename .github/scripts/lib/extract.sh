#!/bin/bash
# Extract source archives

# Extract source archive
# Usage: extract_source <archive> <dest_dir>
# Returns: dest_dir (stdout)
extract_source() {
    local archive="$1"
    local dest_dir="$2"

    mkdir -p "$dest_dir"

    echo -e "${BLUE}→ Extracting to ${dest_dir}...${NC}" >&2

    local filename
    filename=$(basename "$archive")

    if [[ "$filename" == *.tar.gz ]] || [[ "$filename" == *.tgz ]]; then
        tar -xzf "$archive" -C "$dest_dir" --strip-components=1 >/dev/null 2>&1
    elif [[ "$filename" == *.tar.bz2 ]]; then
        tar -xjf "$archive" -C "$dest_dir" --strip-components=1 >/dev/null 2>&1
    elif [[ "$filename" == *.tar.xz ]]; then
        tar -xJf "$archive" -C "$dest_dir" --strip-components=1 >/dev/null 2>&1
    elif [[ "$filename" == *.zip ]]; then
        unzip -q "$archive" -d "$dest_dir"
        # For zip files, check if there's a single root directory
        local count
        count=$(find "$dest_dir" -maxdepth 1 -mindepth 1 | wc -l | tr -d ' ')
        if [ "$count" -eq 1 ]; then
            local root_dir
            root_dir=$(find "$dest_dir" -maxdepth 1 -mindepth 1)
            if [ -d "$root_dir" ]; then
                # Move contents up one level
                mv "$root_dir"/* "$dest_dir"/ 2>/dev/null || true
                mv "$root_dir"/.[!.]* "$dest_dir"/ 2>/dev/null || true
                rmdir "$root_dir"
            fi
        fi
    elif [[ "$filename" == *.pem ]]; then
        # Just copy PEM files
        cp "$archive" "$dest_dir/" >/dev/null 2>&1
    else
        echo -e "${RED}✗ Unknown archive format: $filename${NC}" >&2
        return 1
    fi

    echo "$dest_dir"
}
