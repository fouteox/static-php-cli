#!/bin/bash
# Build recipe for valkey 8.1.4
# Translated from: homebrew-core/Formula/v/valkey.rb
# Description: High-performance data structure server that primarily serves key/value workloads

set -e

# Metadata
export PACKAGE_NAME="valkey"
export PACKAGE_VERSION="8.1.4"
export PACKAGE_URL="https://github.com/valkey-io/valkey/archive/refs/tags/8.1.4.tar.gz"
export PACKAGE_SHA256="32350b017fee5e1a85f7e2d8580d581a0825ceae5cb3395075012c0970694dee"

# Runtime dependencies
export DEPENDENCIES=(
    "openssl@3"
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

    # Build with make (valkey doesn't use configure)
    # BUILD_TLS=yes enables TLS support with OpenSSL
    make -j"$(sysctl -n hw.ncpu)" \
        PREFIX="${PREFIX}" \
        CC="${CC:-cc}" \
        BUILD_TLS=yes

    # Install directly to final location
    make install PREFIX="${PREFIX}"

    echo "✓ ${PACKAGE_NAME} built successfully"
}
