#!/bin/bash
# Build recipe for krb5 1.22.1
# Translated from: homebrew-core/Formula/k/krb5.rb

set -e

# Metadata
export PACKAGE_NAME="krb5"
export PACKAGE_VERSION="1.22.1"
export PACKAGE_URL="https://kerberos.org/dist/krb5/1.22/krb5-1.22.1.tar.gz"
export PACKAGE_SHA256="1a8832b8cad923ebbf1394f67e2efcf41e3a49f460285a66e35adec8fa0053af"

# Runtime dependencies (must be built first)
export DEPENDENCIES=(
    "openssl@3"
)

# Build function
build() {
    local PREFIX="$1"
    local SOURCE_DIR="$2"

    echo "Building krb5 ${PACKAGE_VERSION}..."

    # Dependencies are installed in $PREFIX (parent_prefix logic)
    export PKG_CONFIG_PATH="${PREFIX}/lib/pkgconfig"
    export CPPFLAGS="-I${PREFIX}/include"
    # Add headerpad for install_name_tool (CRITICAL for relocation)
    export LDFLAGS="-L${PREFIX}/lib -Wl,-headerpad_max_install_names"

    # Change to src directory (krb5 builds from src/)
    cd "${SOURCE_DIR}/src"

    # Configure
    ./configure \
        --prefix="${PREFIX}" \
        --disable-nls \
        --disable-silent-rules \
        --without-system-verto \
        --without-keyutils

    # Build
    make -j"$(sysctl -n hw.ncpu)"

    # Install directly to final location
    make install

    echo "✓ krb5 built successfully"
}
