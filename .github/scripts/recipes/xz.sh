#!/bin/bash
# Build recipe for xz 5.8.1
# Translated from: homebrew-core/Formula/x/xz.rb
# Description: General-purpose data compression with high compression ratio

set -e

# Metadata
export PACKAGE_NAME="xz"
export PACKAGE_VERSION="5.8.1"
export PACKAGE_URL="https://github.com/tukaani-project/xz/releases/download/v5.8.1/xz-5.8.1.tar.gz"
export PACKAGE_SHA256="507825b599356c10dca1cd720c9d0d0c9d5400b9de300af00e4d1ea150795543"

# Runtime dependencies
export DEPENDENCIES=(
)

# Build function
build() {
    local PREFIX="$1"
    local SOURCE_DIR="$2"

    echo "Building ${PACKAGE_NAME} ${PACKAGE_VERSION}..."

    # Dependencies are installed in $PREFIX (parent_prefix logic)
    export PKG_CONFIG_PATH="${PREFIX}/lib/pkgconfig"
    export CPPFLAGS="-I${PREFIX}/include"
    # Add headerpad for install_name_tool (CRITICAL for relocation)
    export LDFLAGS="-L${PREFIX}/lib -Wl,-headerpad_max_install_names"

    cd "${SOURCE_DIR}"

    # Configure
    ./configure \
        --prefix="${PREFIX}" \
        --disable-silent-rules \
        --disable-nls

    # Build
    make -j"$(sysctl -n hw.ncpu)"

    # Run tests (as per Homebrew formula)
    echo "→ Running tests..."
    make check

    # Install directly to final location
    make install

    echo "✓ ${PACKAGE_NAME} built successfully"
}
