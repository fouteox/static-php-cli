#!/bin/bash
# Build recipe for PostgreSQL 14.x
# Translated from: homebrew-core/Formula/p/postgresql@14.rb
# Description: Object-relational database system

set -e

# Load helpers
source "$(dirname "${BASH_SOURCE[0]}")/../lib/recipe-helpers.sh"

# Metadata
export PACKAGE_VERSION="14.20"
export PACKAGE_SHA256="7527f10f1640761bc280ad97d105d286d0cf72e54d36d78cf68e5e5f752b646b"

# Derived automatically
PACKAGE_NAME="$(get_package_name)"
PACKAGE_URL="$(get_package_url postgresql "$PACKAGE_VERSION")"
export PACKAGE_NAME PACKAGE_URL

# Runtime dependencies
export DEPENDENCIES=(
    "icu4c@78"
    "krb5"
    "lz4"
    "openssl@3"
    "readline"
)

# Build dependencies (via Homebrew, not in bundle)
export BUILD_DEPENDENCIES=(
    "pkgconf"
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

    # Configure PostgreSQL
    ./configure \
        --prefix="${PREFIX}" \
        --datadir="${PREFIX}/share/postgresql" \
        --libdir="${PREFIX}/lib/postgresql" \
        --includedir="${PREFIX}/include/postgresql" \
        --disable-debug \
        --enable-thread-safety \
        --with-gssapi \
        --with-icu \
        --with-ldap \
        --with-libxml \
        --with-libxslt \
        --with-lz4 \
        --with-openssl \
        --with-pam \
        --with-perl \
        --with-uuid=e2fs \
        --with-bonjour \
        --with-tcl

    # Build
    make -j"$(sysctl -n hw.ncpu)"

    # Install directly to final location
    make install-world \
        datadir="${PREFIX}/share/postgresql" \
        libdir="${PREFIX}/lib/postgresql" \
        pkglibdir="${PREFIX}/lib/postgresql" \
        includedir="${PREFIX}/include/postgresql" \
        pkgincludedir="${PREFIX}/include/postgresql" \
        includedir_server="${PREFIX}/include/postgresql/server" \
        includedir_internal="${PREFIX}/include/postgresql/internal"

    echo "✓ ${PACKAGE_NAME} built successfully"
}
