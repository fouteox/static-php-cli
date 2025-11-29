#!/bin/bash
# Build recipe for NSS 3.117
# Using gyp/ninja build system (recommended by Mozilla)
# Description: Network Security Services

set -e

# Metadata
export PACKAGE_NAME="nss@3"
export PACKAGE_VERSION="3.118"
export PACKAGE_URL="https://ftp.mozilla.org/pub/security/nss/releases/NSS_3_118_RTM/src/nss-3.118-with-nspr-4.37.tar.gz"
export PACKAGE_SHA256="14253b498babbcddc36e65df531292f69f7359bc975ca082a5801ee4147a7acc"

# Runtime dependencies (none - NSPR built together with NSS via build.sh)
export DEPENDENCIES=()

# Build dependencies (via Homebrew, not included in bundle)
export BUILD_DEPENDENCIES=(
    "python@3.13"
)

# Build function
build() {
    local PREFIX="$1"
    local SOURCE_DIR="$2"

    echo "Building ${PACKAGE_NAME} ${PACKAGE_VERSION}..."

    # Ensure python (not just python3) is in PATH for NSS build system
    if ! command -v python >/dev/null 2>&1; then
        export PATH="/opt/homebrew/opt/python/libexec/bin:$PATH"
    fi

    # Install build tools in temporary venv (PEP 668 compliant)
    if ! python3 -c "import gyp" >/dev/null 2>&1; then
        echo "→ Installing build tools in temporary venv..."
        python3 -m venv "${BUILD_DIR}/.venv-gyp"
        "${BUILD_DIR}/.venv-gyp/bin/pip" install --quiet gyp-next ninja
        export PATH="${BUILD_DIR}/.venv-gyp/bin:$PATH"
        echo "  ✓ gyp-next and ninja ready"
    fi

    # Build NSS using gyp/ninja (automatically builds NSPR too)
    cd "${SOURCE_DIR}/nss"
    echo "→ Building NSS with gyp/ninja (includes NSPR)..."
    echo "  This will take several minutes..."

    # -o = optimized/release mode (not debug)
    # -c = clean before build
    ./build.sh -o -c

    # Verify dist directory was created
    local DIST_DIR="${SOURCE_DIR}/dist"
    if [ ! -d "$DIST_DIR" ]; then
        echo "Error: dist directory not found at ${DIST_DIR}"
        exit 1
    fi

    echo "→ Installing to ${PREFIX}..."

    # Copy all built files from dist to PREFIX
    mkdir -p "${PREFIX}"

    # Find the Release directory (architecture-specific)
    local RELEASE_DIR
    RELEASE_DIR=$(find "${DIST_DIR}" -maxdepth 1 -type d -name "Release" | head -1)

    if [ -z "$RELEASE_DIR" ]; then
        echo "Error: Release directory not found in dist"
        exit 1
    fi

    echo "  Using: ${RELEASE_DIR}"

    # Copy binaries
    if [ -d "${RELEASE_DIR}/bin" ]; then
        mkdir -p "${PREFIX}/bin"
        cp -R "${RELEASE_DIR}/bin/"* "${PREFIX}/bin/" 2>/dev/null || true
    fi

    # Copy libraries
    if [ -d "${RELEASE_DIR}/lib" ]; then
        mkdir -p "${PREFIX}/lib"
        cp -R "${RELEASE_DIR}/lib/"* "${PREFIX}/lib/" 2>/dev/null || true
    fi

    # Copy includes (optional, for completeness)
    if [ -d "${DIST_DIR}/public" ]; then
        mkdir -p "${PREFIX}/include"
        cp -R "${DIST_DIR}/public/"* "${PREFIX}/include/" 2>/dev/null || true
    fi

    echo "✓ ${PACKAGE_NAME} built successfully"
    echo "  Package includes NSS + NSPR (built via gyp/ninja)"
}
