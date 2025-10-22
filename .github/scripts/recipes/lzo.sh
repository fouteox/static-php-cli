#!/bin/bash
# Build recipe for lzo 2.10
# Translated from: homebrew-core/Formula/l/lzo.rb
# Description: Real-time data compression library

set -e

# Metadata
export PACKAGE_NAME="lzo"
export PACKAGE_VERSION="2.10"
export PACKAGE_URL="https://www.oberhumer.com/opensource/lzo/download/lzo-2.10.tar.gz"
export PACKAGE_SHA256="c0f892943208266f9b6543b3ae308fab6284c5c90e627931446fb49b4221a072"

# No runtime dependencies
export DEPENDENCIES=()

# Build dependencies (via Homebrew, not in bundle)
export BUILD_DEPENDENCIES=()

# Build function
build() {
    local PREFIX="$1"
    local SOURCE_DIR="$2"

    echo "Building ${PACKAGE_NAME} ${PACKAGE_VERSION}..."

    cd "${SOURCE_DIR}"

    # Configure
    ./configure \
        --disable-dependency-tracking \
        --prefix="${PREFIX}" \
        --enable-shared

    # Build
    make -j"$(sysctl -n hw.ncpu)"

    # Test
    make check

    # Install
    make install

    echo "✓ ${PACKAGE_NAME} built successfully"
}
