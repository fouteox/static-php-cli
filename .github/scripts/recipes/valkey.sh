#!/bin/bash
# Build recipe for Valkey
# Translated from: homebrew-core/Formula/v/valkey.rb
# Description: High-performance data structure server that primarily serves key/value workloads

set -e

# Load helpers
source "$(dirname "${BASH_SOURCE[0]}")/../lib/recipe-helpers.sh"

# Metadata
export PACKAGE_VERSION="9.0.0"
export PACKAGE_SHA256="088f47e167eb640ea31af48c81c5d62ee56321f25a4b05d4e54a0ef34232724b"

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
