#!/bin/bash
# Build recipe for postgresql@15 15.14
# Translated from: homebrew-core/Formula/p/postgresql@15.rb
# Description: Object-relational database system

set -e

# Metadata
export PACKAGE_NAME="postgresql@15"
export PACKAGE_VERSION="15.14"
export PACKAGE_URL="https://ftp.postgresql.org/pub/source/v15.14/postgresql-15.14.tar.bz2"
export PACKAGE_SHA256="06dd75d305cd3870ee62b3932e661c624543eaf9ae2ba37cdec0a4f8edd051d2"

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
