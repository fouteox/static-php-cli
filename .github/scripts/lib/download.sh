#!/bin/bash
# Download and verify package archives

# Download and verify package
# Usage: download_package <url> <sha256>
# Returns: filepath (stdout)
download_package() {
    local url="$1"
    local sha256="$2"

    local filename
    filename=$(basename "$url")
    local filepath="${DOWNLOADS_DIR}/${filename}"

    mkdir -p "${DOWNLOADS_DIR}"

    # Download if not cached
    if [ ! -f "$filepath" ]; then
        echo -e "${BLUE}→ Downloading ${filename}...${NC}" >&2
        curl -L -o "$filepath" "$url" >/dev/null 2>&1
    else
        echo -e "${YELLOW}↺ Using cached ${filename}${NC}" >&2
    fi

    # Verify checksum
    echo -e "${BLUE}→ Verifying checksum...${NC}" >&2
    local actual_sha256
    actual_sha256=$(shasum -a 256 "$filepath" | awk '{print $1}')
    if [ "$actual_sha256" != "$sha256" ]; then
        echo -e "${RED}✗ Checksum mismatch!${NC}" >&2
        echo -e "  Expected: $sha256" >&2
        echo -e "  Actual:   $actual_sha256" >&2
        return 1
    fi
    echo -e "${GREEN}✓ Checksum verified${NC}" >&2

    # Return ONLY the filepath (to stdout)
    echo "$filepath"
}
