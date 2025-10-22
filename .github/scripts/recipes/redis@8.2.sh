#!/bin/bash
# Build recipe for redis 8.2.2
# Translated from: homebrew-core/Formula/r/redis.rb
# Description: Persistent key-value database, with built-in net interface

set -e

# Metadata
export PACKAGE_NAME="redis"
export PACKAGE_VERSION="8.2.2"
export PACKAGE_URL="https://download.redis.io/releases/redis-8.2.2.tar.gz"
export PACKAGE_SHA256="4e340e8e822a82114b6fb0f7ca581b749fa876e31e36e9fbcb75416bec9d0608"

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

    # Build with make (redis doesn't use configure)
    # BUILD_TLS=yes enables TLS support with OpenSSL
    make -j"$(sysctl -n hw.ncpu)" \
        PREFIX="${PREFIX}" \
        CC="${CC:-cc}" \
        BUILD_TLS=yes

    # Install directly to final location
    make install PREFIX="${PREFIX}"

    echo "✓ ${PACKAGE_NAME} built successfully"
}
