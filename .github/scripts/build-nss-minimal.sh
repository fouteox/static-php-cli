#!/bin/bash

# Build NSS from source and create a minimal portable package
# Usage: ./build-nss-minimal.sh <recipe-name>
# Example: ./build-nss-minimal.sh nss@3
#
# Output: nss-{version}.tar.gz with portable structure:
#   certutil            (main binary)
#   lib/*.dylib         (all NSS/NSPR libraries)
#
# All rpaths are relative (@executable_path/lib/*)

set -e

# Save initial working directory for archive creation
INITIAL_PWD="$PWD"

# Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RECIPES_DIR="${SCRIPT_DIR}/recipes"

# Load library functions
source "${SCRIPT_DIR}/lib/colors.sh"
source "${SCRIPT_DIR}/lib/download.sh"
source "${SCRIPT_DIR}/lib/extract.sh"

# Ensure build dependencies are installed via Homebrew
ensure_build_dependencies() {
    local build_deps="$1"

    if [ -z "$build_deps" ]; then
        return 0
    fi

    echo -e "${BLUE}→ Checking build dependencies...${NC}"

    for dep in $build_deps; do
        if brew list "$dep" &>/dev/null; then
            echo -e "  ${GREEN}✓${NC} $dep"
        else
            echo -e "  ${YELLOW}→ Installing${NC} $dep via Homebrew..."
            brew install "$dep" || {
                echo -e "${RED}✗ Failed to install: $dep${NC}"
                return 1
            }
        fi
    done
}

# Create temporary build directory in /tmp
BUILD_DIR=$(mktemp -d /tmp/nss-build)
export DOWNLOADS_DIR="${BUILD_DIR}/downloads"
SOURCES_DIR="${BUILD_DIR}/src"

# Cleanup function
cleanup() {
    if [ -n "${BUILD_DIR:-}" ] && [ -d "$BUILD_DIR" ]; then
        echo -e "${YELLOW}→ Cleaning up build directory...${NC}"
        rm -rf "$BUILD_DIR"
    fi
}
trap cleanup EXIT

# Main
if [ $# -eq 0 ]; then
    echo "Usage: $0 <recipe-name>"
    echo "Example: $0 nss@3"
    exit 1
fi

RECIPE_NAME="$1"
RECIPE_FILE="${RECIPES_DIR}/${RECIPE_NAME}.sh"

if [ ! -f "$RECIPE_FILE" ]; then
    echo -e "${RED}✗ Recipe not found: $RECIPE_FILE${NC}"
    exit 1
fi

echo -e "${GREEN}=== Building NSS minimal portable package ===${NC}"
echo -e "Recipe: ${BLUE}${RECIPE_NAME}${NC}"
echo -e "Build directory: ${BLUE}${BUILD_DIR}${NC}"
echo -e ""

# Extract recipe metadata
recipe_info=$(
    # shellcheck source=/dev/null
    source "$RECIPE_FILE"
    # shellcheck disable=SC2153
    echo "VERSION=${PACKAGE_VERSION}"
    echo "URL=${PACKAGE_URL}"
    echo "SHA256=${PACKAGE_SHA256}"
    echo "BUILD_DEPS=${BUILD_DEPENDENCIES[*]}"
)

PKG_VERSION=$(echo "$recipe_info" | grep "^VERSION=" | cut -d= -f2-)
PKG_URL=$(echo "$recipe_info" | grep "^URL=" | cut -d= -f2-)
PKG_SHA256=$(echo "$recipe_info" | grep "^SHA256=" | cut -d= -f2-)
PKG_BUILD_DEPS=$(echo "$recipe_info" | grep "^BUILD_DEPS=" | cut -d= -f2-)

# Ensure build dependencies are installed
if [ -n "$PKG_BUILD_DEPS" ]; then
    ensure_build_dependencies "$PKG_BUILD_DEPS"
    echo ""
fi

echo -e "${GREEN}━━━ Step 1: Download and extract source ━━━${NC}"

# Download source
echo -e "${BLUE}→ Downloading NSS ${PKG_VERSION}${NC}"
mkdir -p "$DOWNLOADS_DIR"
ARCHIVE_PATH=$(download_package "$PKG_URL" "$PKG_SHA256")

# Extract source
SOURCE_DIR="${SOURCES_DIR}/${RECIPE_NAME}"
mkdir -p "$SOURCES_DIR"
extract_source "$ARCHIVE_PATH" "$SOURCE_DIR"
echo -e "${GREEN}✓ Source ready at ${SOURCE_DIR}${NC}\n"

echo -e "${GREEN}━━━ Step 2: Compile NSS ━━━${NC}"

# Create temporary install prefix
INSTALL_PREFIX="${BUILD_DIR}/install"
mkdir -p "$INSTALL_PREFIX"

echo -e "${BLUE}→ Compiling to temporary prefix: ${INSTALL_PREFIX}${NC}"

# Call the build() function from the recipe
(
    # shellcheck source=/dev/null
    source "$RECIPE_FILE"
    cd "$SOURCE_DIR"
    build "$INSTALL_PREFIX" "$SOURCE_DIR"
)

echo -e "${GREEN}✓ Compilation complete${NC}\n"

echo -e "${GREEN}━━━ Step 3: Create portable package structure ━━━${NC}"

# Create clean directory structure
CLEAN_DIR="${BUILD_DIR}/nss-${PKG_VERSION}"
mkdir -p "$CLEAN_DIR/lib"

echo -e "${BLUE}→ Copying certutil binary${NC}"
if [ ! -f "${INSTALL_PREFIX}/bin/certutil" ]; then
    echo -e "${RED}✗ Error: certutil not found at ${INSTALL_PREFIX}/bin/certutil${NC}"
    exit 1
fi
cp "${INSTALL_PREFIX}/bin/certutil" "$CLEAN_DIR/certutil"
echo -e "  ✓ certutil"

echo -e "${BLUE}→ Copying ALL dynamic libraries (automatic detection)${NC}"
DYLIB_COUNT=0
if [ -d "${INSTALL_PREFIX}/lib" ]; then
    while IFS= read -r dylib; do
        cp "$dylib" "$CLEAN_DIR/lib/"
        echo -e "  ✓ $(basename "$dylib")"
        DYLIB_COUNT=$((DYLIB_COUNT + 1))
    done < <(find "${INSTALL_PREFIX}/lib" -name "*.dylib" -type f)
else
    echo -e "${RED}✗ Error: lib directory not found at ${INSTALL_PREFIX}/lib${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Copied ${DYLIB_COUNT} dynamic libraries${NC}\n"

echo -e "${GREEN}━━━ Step 4: Fix rpaths for portability ━━━${NC}"

cd "$CLEAN_DIR"

echo -e "${BLUE}→ Fixing certutil rpaths${NC}"
# Get all dylib references from certutil
while IFS= read -r linked_lib; do
    # Skip system libraries
    [[ "$linked_lib" =~ ^/usr/lib/ ]] && continue
    [[ "$linked_lib" =~ ^/System/ ]] && continue

    lib_basename=$(basename "$linked_lib")

    # Check if this library exists in our lib/ directory
    if [ -f "lib/$lib_basename" ]; then
        echo -e "  Changing: $lib_basename"
        echo -e "    Old: $linked_lib"
        echo -e "    New: @executable_path/lib/$lib_basename"
        install_name_tool -change "$linked_lib" "@executable_path/lib/$lib_basename" certutil 2>/dev/null || {
            echo -e "${YELLOW}    Warning: Failed to change path for $lib_basename${NC}"
        }
    fi
done < <(otool -L certutil 2>/dev/null | tail -n +2 | awk '{print $1}' | grep -v ":")

echo -e "${BLUE}→ Fixing dylib rpaths and IDs${NC}"
# Process each dylib
for dylib in lib/*.dylib; do
    [ ! -f "$dylib" ] && continue

    lib_name=$(basename "$dylib")
    echo -e "  Processing: $lib_name"

    # 1. Fix dylib ID
    current_id=$(otool -D "$dylib" 2>/dev/null | sed -n '2p' || echo "")
    if [ -n "$current_id" ] && [ "$current_id" != "@executable_path/lib/$lib_name" ]; then
        echo -e "    ID: @executable_path/lib/$lib_name"
        install_name_tool -id "@executable_path/lib/$lib_name" "$dylib" 2>/dev/null || {
            echo -e "${YELLOW}    Warning: Failed to change ID${NC}"
        }
    fi

    # 2. Fix all dependency references
    while IFS= read -r linked_lib; do
        # Skip system libraries
        [[ "$linked_lib" =~ ^/usr/lib/ ]] && continue
        [[ "$linked_lib" =~ ^/System/ ]] && continue

        # Skip if already using @executable_path/lib/ (correct path)
        [[ "$linked_lib" =~ ^@executable_path/lib/ ]] && continue

        dep_basename=$(basename "$linked_lib")

        # Check if this dependency exists in our lib/ directory
        if [ -f "lib/$dep_basename" ]; then
            echo -e "    Dep: $dep_basename → @executable_path/lib/$dep_basename"
            install_name_tool -change "$linked_lib" "@executable_path/lib/$dep_basename" "$dylib" 2>/dev/null || {
                echo -e "${YELLOW}    Warning: Failed to change dependency${NC}"
            }
        fi
    done < <(otool -L "$dylib" 2>/dev/null | tail -n +2 | awk '{print $1}' | grep -v ":")
done

echo -e "${GREEN}✓ Rpaths fixed for portability${NC}\n"

echo -e "${GREEN}━━━ Step 5: Create archive ━━━${NC}"

cd "${BUILD_DIR}"
ARCHIVE_NAME="nss-${PKG_VERSION}.tar.gz"

echo -e "${BLUE}→ Creating archive: ${ARCHIVE_NAME}${NC}"
tar -czf "$ARCHIVE_NAME" -C "$CLEAN_DIR" . || {
    echo -e "${RED}✗ Failed to create archive${NC}"
    exit 1
}

# Move archive to initial working directory
mv "$ARCHIVE_NAME" "${INITIAL_PWD}/" || {
    echo -e "${RED}✗ Failed to move archive${NC}"
    exit 1
}

cd "${INITIAL_PWD}"

ARCHIVE_SIZE=$(du -sh "$ARCHIVE_NAME" 2>/dev/null | awk '{print $1}' || echo "unknown")

echo -e "${GREEN}✓ Archive created successfully${NC}\n"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}Build complete!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e ""
echo -e "${BLUE}Archive info:${NC}"
echo -e "  File: ${ARCHIVE_NAME} (${ARCHIVE_SIZE})"
echo -e "  Binaries: 1 (certutil)"
echo -e "  Libraries: ${DYLIB_COUNT}"
echo -e ""
echo -e "${BLUE}Verification commands:${NC}"
echo -e "  1. Extract: tar -xzf ${ARCHIVE_NAME}"
echo -e "  2. Check rpaths: otool -L certutil"
echo -e "  3. Test: ./certutil -h"
echo -e ""
