#!/bin/bash
# Build recipe for postgresql@16 16.10
# Translated from: homebrew-core/Formula/p/postgresql@16.rb
# Description: Object-relational database system

set -e

# Metadata
export PACKAGE_NAME="postgresql@16"
export PACKAGE_VERSION="16.10"
export PACKAGE_URL="https://ftp.postgresql.org/pub/source/v16.10/postgresql-16.10.tar.bz2"
export PACKAGE_SHA256="de8485f4ce9c32e3ddfeef0b7c261eed1cecb54c9bcd170e437ff454cb292b42"

# Runtime dependencies
export DEPENDENCIES=(
    "icu4c@77"
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
