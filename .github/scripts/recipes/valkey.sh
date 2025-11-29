#!/bin/bash
# Build recipe for Valkey 8.x
# Translated from: homebrew-core/Formula/v/valkey.rb
# Description: High-performance data structure server that primarily serves key/value workloads

set -e

# Load helpers
source "$(dirname "${BASH_SOURCE[0]}")/../lib/recipe-helpers.sh"

# Metadata
export PACKAGE_VERSION="8.1.4"
export PACKAGE_SHA256="32350b017fee5e1a85f7e2d8580d581a0825ceae5cb3395075012c0970694dee"

# Derived automatically
PACKAGE_NAME="$(get_package_name)"
PACKAGE_URL="$(get_package_url valkey "$PACKAGE_VERSION")"
export PACKAGE_NAME PACKAGE_URL

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
