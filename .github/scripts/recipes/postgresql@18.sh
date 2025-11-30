#!/bin/bash
# Build recipe for PostgreSQL 18.x
# Translated from: homebrew-core/Formula/p/postgresql@18.rb
# Description: Object-relational database system

set -e

# Load helpers
source "$(dirname "${BASH_SOURCE[0]}")/../lib/recipe-helpers.sh"

# Metadata
export PACKAGE_VERSION="18.1"
export PACKAGE_SHA256="ff86675c336c46e98ac991ebb306d1b67621ece1d06787beaade312c2c915d54"

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
    "docbook"
    "docbook-xsl"
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

    # Set XML catalog for docbook (installed via Homebrew as build dep)
    if [ -f "/opt/homebrew/etc/xml/catalog" ]; then
        export XML_CATALOG_FILES="/opt/homebrew/etc/xml/catalog"
    elif [ -f "/usr/local/etc/xml/catalog" ]; then
        export XML_CATALOG_FILES="/usr/local/etc/xml/catalog"  # Intel Mac
    fi

    cd "${SOURCE_DIR}"

    # Modify Makefile.shlib to use correct install_name for dylibs
    echo "→ Patching Makefile.shlib for correct dylib paths..."
    sed -i '' "s|-install_name '\$(libdir)/|-install_name '${PREFIX}/lib/postgresql/|" src/Makefile.shlib

    # Configure PostgreSQL
    ./configure \
        --prefix="${PREFIX}" \
        --datadir="${PREFIX}/share/postgresql" \
        --includedir="${PREFIX}/include/postgresql" \
        --sysconfdir="${PREFIX}/etc" \
        --docdir="${PREFIX}/share/doc/postgresql" \
        --libdir="${PREFIX}/lib/postgresql" \
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

    # Build
    make -j"$(sysctl -n hw.ncpu)"

    # Install directly to final location
    make install-world \
        datadir="${PREFIX}/share/postgresql" \
        libdir="${PREFIX}/lib/postgresql" \
        includedir="${PREFIX}/include/postgresql"

    # Restore Makefile.shlib for dependents
    local MAKEFILE="${PREFIX}/lib/postgresql/pgxs/src/Makefile.shlib"
    if [ -f "$MAKEFILE" ]; then
        sed -i '' "s|-install_name '${PREFIX}/lib/postgresql/|-install_name '\$(libdir)/|" "$MAKEFILE"
    fi

    echo "✓ ${PACKAGE_NAME} built successfully"
}
