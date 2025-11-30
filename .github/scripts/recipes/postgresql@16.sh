#!/bin/bash
# Build recipe for PostgreSQL 16.x
# Translated from: homebrew-core/Formula/p/postgresql@16.rb
# Description: Object-relational database system

set -e

# Load helpers
source "$(dirname "${BASH_SOURCE[0]}")/../lib/recipe-helpers.sh"

# Metadata
export PACKAGE_VERSION="16.11"
export PACKAGE_SHA256="6deb08c23d03d77d8f8bd1c14049eeef64aef8968fd8891df2dfc0b42f178eac"

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
    "zstd"
    "gettext"
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
        --libdir="${PREFIX}/lib" \
        --includedir="${PREFIX}/include" \
        --sysconfdir="${PREFIX}/etc" \
        --docdir="${PREFIX}/share/doc/postgresql" \
        --enable-nls \
        --enable-thread-safety \
        --with-gssapi \
        --with-icu \
        --with-ldap \
        --with-libxml \
        --with-libxslt \
        --with-lz4 \
        --with-zstd \
        --with-openssl \
        --with-pam \
        --with-perl \
        --with-uuid=e2fs \
        --with-bonjour \
        --with-tcl

    # Build (with path workaround for Makefile.global.in bug)
    # See https://github.com/Homebrew/homebrew-core/issues/62930#issuecomment-709411789
    make -j"$(sysctl -n hw.ncpu)" \
        pkglibdir="${PREFIX}/lib/postgresql" \
        pkgincludedir="${PREFIX}/include/postgresql" \
        includedir_server="${PREFIX}/include/postgresql/server"

    # Install directly to final location
    make install-world \
        datadir="${PREFIX}/share/postgresql" \
        libdir="${PREFIX}/lib" \
        pkglibdir="${PREFIX}/lib/postgresql" \
        includedir="${PREFIX}/include" \
        pkgincludedir="${PREFIX}/include/postgresql" \
        includedir_server="${PREFIX}/include/postgresql/server" \
        includedir_internal="${PREFIX}/include/postgresql/internal"

    echo "✓ ${PACKAGE_NAME} built successfully"
}
