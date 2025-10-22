#!/opt/homebrew/bin/bash

# Build packages from source using recipe files
# Usage: ./build-from-recipes.sh <package-name> [--staging <dir>]
#
# Architecture:
#   lib/colors.sh    - Color definitions for terminal output
#   lib/download.sh  - Download and checksum verification
#   lib/extract.sh   - Archive extraction
#   recipes/*.sh     - Package recipes (metadata + build function)
#
# This script orchestrates recursive package builds with dependency resolution.

set -e

# Save initial working directory for archive creation
INITIAL_PWD="$PWD"

# Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RECIPES_DIR="${SCRIPT_DIR}/recipes"
BUILD_DIR="${SCRIPT_DIR}/build"
export DOWNLOADS_DIR="${BUILD_DIR}/downloads"
SOURCES_DIR="${BUILD_DIR}/src"

# Load library functions
source "${SCRIPT_DIR}/lib/colors.sh"
source "${SCRIPT_DIR}/lib/download.sh"
source "${SCRIPT_DIR}/lib/extract.sh"
source "${SCRIPT_DIR}/lib/relocate.sh"

# Final installation prefix (Fadogen style - fixed path)
FADOGEN_BASE="/Users/Shared/Fadogen"

# Tracking built packages and versions
declare -A BUILT_PACKAGES
declare -A PACKAGE_VERSIONS
declare -a BUILT_PACKAGES_ORDER  # Ordered list for post_install (topological order)

# Ensure build dependencies are installed via Homebrew (not included in bundle)
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

# Run post_install() for all packages in the bundle
run_post_installs() {
    local prefix="$1"
    shift  # Remove first argument, rest are package names
    local packages=("$@")

    if [ ${#packages[@]} -eq 0 ]; then
        return 0
    fi

    echo -e "${GREEN}━━━ Running post-install scripts ━━━${NC}"

    for pkg_name in "${packages[@]}"; do
        local recipe_file="${RECIPES_DIR}/${pkg_name}.sh"

        if [ ! -f "$recipe_file" ]; then
            continue
        fi

        # Check if recipe defines post_install function
        (
            # shellcheck source=/dev/null
            source "$recipe_file"
            if declare -F post_install > /dev/null 2>&1; then
                echo -e "${BLUE}→ Running post_install for ${pkg_name}${NC}"
                post_install "$prefix"
            fi
        )
    done

    echo -e "${GREEN}✓ Post-install scripts completed${NC}\n"
}

# Build a package from its recipe (recursive with dependency resolution)
build_package() {
    local package_name="$1"
    local indent="$2"
    local parent_prefix="$3"  # If building as a dependency, use parent's prefix

    # Skip if already built in this session
    if [ -n "${BUILT_PACKAGES[$package_name]}" ]; then
        echo -e "${indent}${YELLOW}↺ $package_name (already built in this session)${NC}"
        return 0
    fi

    echo -e "${indent}${GREEN}━━━ Building: $package_name ━━━${NC}"

    # Load recipe in a subshell to avoid variable pollution
    local recipe_file="${RECIPES_DIR}/${package_name}.sh"
    if [ ! -f "$recipe_file" ]; then
        echo -e "${indent}${RED}✗ Recipe not found: $recipe_file${NC}"
        return 1
    fi

    # Extract recipe metadata in subshell
    local recipe_info
    # shellcheck source=/dev/null
    recipe_info=$(
        source "$recipe_file"
        # shellcheck disable=SC2153
        echo "VERSION=${PACKAGE_VERSION}"
        echo "URL=${PACKAGE_URL}"
        echo "SHA256=${PACKAGE_SHA256}"
        echo "DEPS=${DEPENDENCIES[*]}"
        echo "BUILD_DEPS=${BUILD_DEPENDENCIES[*]}"
    )

    # Parse extracted info
    local pkg_version
    pkg_version=$(echo "$recipe_info" | grep "^VERSION=" | cut -d= -f2-)
    local pkg_url
    pkg_url=$(echo "$recipe_info" | grep "^URL=" | cut -d= -f2-)
    local pkg_sha256
    pkg_sha256=$(echo "$recipe_info" | grep "^SHA256=" | cut -d= -f2-)
    local pkg_deps
    pkg_deps=$(echo "$recipe_info" | grep "^DEPS=" | cut -d= -f2-)
    local pkg_build_deps
    pkg_build_deps=$(echo "$recipe_info" | grep "^BUILD_DEPS=" | cut -d= -f2-)

    # Store version for this package
    PACKAGE_VERSIONS[$package_name]=$pkg_version

    # Determine install prefix
    local install_prefix
    if [ -n "$parent_prefix" ]; then
        # Building as a dependency - use parent's prefix (all in same bundle)
        install_prefix="$parent_prefix"
    else
        # Building as main package - use Fadogen path
        # Format: /Users/Shared/Fadogen/redis/8/ (major version only)
        local base_name version_string version_number

        # Extract base name and version string
        if [[ "$package_name" =~ ^(.+)@(.+)$ ]]; then
            base_name="${BASH_REMATCH[1]}"
            version_string="${BASH_REMATCH[2]}"
        else
            base_name="$package_name"
            version_string="$pkg_version"
        fi

        # Extract major version (first number before first dot)
        version_number=$(echo "$version_string" | grep -oE '^[0-9]+' || echo "$version_string")

        install_prefix="${FADOGEN_BASE}/${base_name}/${version_number}"
        echo -e "${indent}${BLUE}Building directly to: ${install_prefix}${NC}"
    fi

    # Create the installation directory
    mkdir -p "$install_prefix"

    # Build dependencies first (using same prefix)
    if [ -n "$pkg_deps" ]; then
        echo -e "${indent}${BLUE}Dependencies:${NC}"
        for dep in $pkg_deps; do
            echo -e "${indent}  • $dep"
            build_package "$dep" "${indent}  " "$install_prefix"
        done
    fi

    # Ensure build tools are available via Homebrew
    if [ -n "$pkg_build_deps" ]; then
        ensure_build_dependencies "$pkg_build_deps"
    fi

    # Download source
    echo -e "${indent}${BLUE}→ Downloading ${package_name} ${pkg_version}${NC}"
    local archive_path
    archive_path=$(download_package "$pkg_url" "$pkg_sha256")

    # Extract source
    local source_dir="${SOURCES_DIR}/${package_name}"
    rm -rf "$source_dir"  # Clean old source
    extract_source "$archive_path" "$source_dir"
    echo -e "${indent}${GREEN}✓ Source ready${NC}"

    # Build
    echo -e "${indent}${GREEN}→ Compiling ${package_name}...${NC}"

    # Call the build() function from the recipe in a subshell
    # Build directly to final location with correct paths
    (
        # shellcheck source=/dev/null
        source "$recipe_file"
        cd "$source_dir"
        build "$install_prefix" "$source_dir"
    )

    # Fix dylib install_name paths (some libraries don't set them correctly)
    # This handles cases like ICU (no path), zstd (@rpath), etc.
    echo -e "${indent}${BLUE}→ Fixing dylib paths...${NC}"
    relocate_macho_files "$install_prefix" "$install_prefix" 2>&1 | sed "s/^/${indent}  /"

    # Mark as built and add to ordered list (for post_install)
    BUILT_PACKAGES[$package_name]=1
    BUILT_PACKAGES_ORDER+=("$package_name")

    # Run post_install() for all packages (only for main package, at the end)
    if [ -z "$parent_prefix" ]; then
        echo -e "${indent}${GREEN}✓ $package_name built successfully${NC}\n"
        run_post_installs "$install_prefix" "${BUILT_PACKAGES_ORDER[@]}"
    else
        echo -e "${indent}${GREEN}✓ $package_name built successfully${NC}\n"
    fi
}

# Main
if [ $# -eq 0 ]; then
    echo "Usage: $0 <package-name>"
    echo "Example: $0 krb5"
    echo ""
    echo "Build strategy:"
    echo "  - Builds directly to: /Users/Shared/Fadogen/<package>/<major-version>/"
    echo "    Example: redis@8.2 -> /Users/Shared/Fadogen/redis/8/"
    echo "  - Binaries are hardcoded for their final location"
    echo "  - No staging - packages are ready to use immediately"
    exit 1
fi

PACKAGE="$1"

echo -e "${GREEN}=== Building $PACKAGE from recipe (Fadogen style) ===${NC}"
echo -e "Fadogen base: ${BLUE}${FADOGEN_BASE}${NC}"
echo -e "Build directory: ${BLUE}${BUILD_DIR}${NC}"
echo -e ""

# Create Fadogen base directory
mkdir -p "$FADOGEN_BASE"

# Build the package (and its dependencies recursively)
build_package "$PACKAGE" ""

# Get the version that was built
PKG_VERSION="${PACKAGE_VERSIONS[$PACKAGE]}"

# Calculate install prefix using same logic as build_package
BASE_NAME=""
VERSION_STRING=""
VERSION_NUMBER=""

if [[ "$PACKAGE" =~ ^(.+)@(.+)$ ]]; then
    BASE_NAME="${BASH_REMATCH[1]}"
    VERSION_STRING="${BASH_REMATCH[2]}"
else
    BASE_NAME="$PACKAGE"
    VERSION_STRING="$PKG_VERSION"
fi

# Extract major version (first number before first dot)
VERSION_NUMBER=$(echo "$VERSION_STRING" | grep -oE '^[0-9]+' || echo "$VERSION_STRING")

INSTALL_PREFIX="${FADOGEN_BASE}/${BASE_NAME}/${VERSION_NUMBER}"

echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}Build complete!${NC}"
echo -e "${GREEN}Total packages built: ${#BUILT_PACKAGES[@]}${NC}"
echo -e "${GREEN}Installed in: ${INSTALL_PREFIX}${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e ""

# Create archive for upload to R2
echo -e "${GREEN}━━━ Creating portable archive ━━━${NC}"

# Archive name format: {service}-{version}.tar.gz (matches R2 metadata format)
ARCHIVE_NAME="${BASE_NAME}-${PKG_VERSION}.tar.gz"
TEMP_BUNDLE="${BUILD_DIR}/${BASE_NAME}-${PKG_VERSION}"

echo -e "${BLUE}→ Preparing bundle structure...${NC}"
rm -rf "$TEMP_BUNDLE"
mkdir -p "$TEMP_BUNDLE"

# Copy built files from install prefix
echo -e "${BLUE}→ Copying files from ${INSTALL_PREFIX}${NC}"
cp -R "${INSTALL_PREFIX}/"* "$TEMP_BUNDLE/" || {
    echo -e "${RED}✗ Failed to copy files${NC}"
    exit 1
}

# Count files before archiving
BIN_COUNT=$(find "$TEMP_BUNDLE/bin" -type f 2>/dev/null | wc -l | tr -d ' ' || echo "0")
LIB_COUNT=$(find "$TEMP_BUNDLE/lib" -name "*.dylib" -type f 2>/dev/null | wc -l | tr -d ' ' || echo "0")

# Create tar.gz archive
echo -e "${BLUE}→ Creating archive: ${ARCHIVE_NAME}${NC}"
cd "${BUILD_DIR}"
tar -czf "${ARCHIVE_NAME}" "$(basename "$TEMP_BUNDLE")" || {
    echo -e "${RED}✗ Failed to create archive${NC}"
    exit 1
}

# Move archive to initial working directory (where workflow expects it)
mv "${ARCHIVE_NAME}" "${INITIAL_PWD}/" || {
    echo -e "${RED}✗ Failed to move archive${NC}"
    exit 1
}

# Cleanup temporary bundle
rm -rf "$TEMP_BUNDLE"

cd "${INITIAL_PWD}"

echo -e "${GREEN}✓ Archive created: ${ARCHIVE_NAME}${NC}"
echo -e ""

ARCHIVE_SIZE=$(du -sh "${ARCHIVE_NAME}" 2>/dev/null | awk '{print $1}' || echo "unknown")

echo -e "${BLUE}Archive info:${NC}"
echo -e "  File: ${ARCHIVE_NAME} (${ARCHIVE_SIZE})"
echo -e "  Binaries: ${BIN_COUNT} | Libraries: ${LIB_COUNT}"
echo -e ""
echo -e "${BLUE}Verification commands:${NC}"
echo -e "  1. Extract: tar -xzf ${ARCHIVE_NAME}"
echo -e "  2. List binaries: ls -lh ${BASE_NAME}-${PKG_VERSION}/bin/"
echo -e "  3. Check dylib paths: otool -L ${BASE_NAME}-${PKG_VERSION}/bin/*"
echo -e ""
