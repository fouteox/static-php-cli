#!/bin/bash
# Build recipe for zlib 1.3.1
# Translated from: homebrew-core/Formula/z/zlib.rb
# Description: General-purpose lossless data-compression library

set -e

# Metadata
export PACKAGE_NAME="zlib"
export PACKAGE_VERSION="1.3.1"
export PACKAGE_URL="https://zlib.net/zlib-1.3.1.tar.gz"
export PACKAGE_SHA256="9a93b2b7dfdac77ceba5a558a580e74667dd6fede4585b91eefb60f03b72df23"

# Runtime dependencies
export DEPENDENCIES=()

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
    ./configure --prefix="${PREFIX}"

    # Build
    make -j"$(sysctl -n hw.ncpu)"

    # Install directly to final location
    make install

    # Fix pkgconfig file to use correct prefix
    local PC_FILE="${PREFIX}/lib/pkgconfig/zlib.pc"
    if [ -f "$PC_FILE" ]; then
        sed -i '' "s|^prefix=.*|prefix=${PREFIX}|" "$PC_FILE"
    fi

    echo "✓ ${PACKAGE_NAME} built successfully"
}
