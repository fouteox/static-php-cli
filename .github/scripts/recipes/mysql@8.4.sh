#!/bin/bash
# Build recipe for MySQL 8.x
# Translated from: homebrew-core/Formula/m/mysql@8.4.rb
# Description: Open source relational database management system

set -e

# Load helpers
source "$(dirname "${BASH_SOURCE[0]}")/../lib/recipe-helpers.sh"

# Metadata
export PACKAGE_VERSION="8.4.6"
export PACKAGE_SHA256="a1e523dc8be96d18a5ade106998661285ca01b6f5b46c08b2654110e40df2fb7"

# Derived automatically
PACKAGE_NAME="$(get_package_name)"
PACKAGE_URL="$(get_package_url mysql "$PACKAGE_VERSION")"
export PACKAGE_NAME PACKAGE_URL

# Runtime dependencies
export DEPENDENCIES=(
    "abseil"
    "icu4c@77"
    "lz4"
    "openssl@3"
    "protobuf@29"
    "zlib"
    "zstd"
)

# Build dependencies (via Homebrew, not in bundle)
export BUILD_DEPENDENCIES=(
    "bison"
    "cmake"
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

    # Find Homebrew bison (MySQL requires newer bison than system provides)
    local BISON_PATH="/opt/homebrew/opt/bison/bin/bison"
    if [ ! -f "$BISON_PATH" ]; then
        BISON_PATH="/usr/local/opt/bison/bin/bison"  # Intel Mac
    fi

    cd "${SOURCE_DIR}"

    # Apply patches
    echo "→ Applying patches..."

    # Patch 1: Remove Homebrew boost check (as per Homebrew formula)
    local PATCH1="${SCRIPT_DIR}/patches/mysql-remove-homebrew-boost-check.patch"
    patch -p1 < "$PATCH1"

    # Patch 2: Fix protobuf/abseil dependencies detection for custom PREFIX
    local PATCH2="${SCRIPT_DIR}/patches/mysql-fix-protobuf-abseil-deps.patch"
    patch -p1 < "$PATCH2"

    echo "✓ Patches applied"

    # Remove bundled libraries other than explicitly allowed (as per Homebrew formula)
    # boost and rapidjson must use bundled copy due to patches
    # lz4 is still needed due to xxhash.c used by mysqlgcs
    echo "→ Removing bundled libraries..."
    local KEEP="boost libbacktrace libcno lz4 rapidjson unordered_dense xxhash"
    for dir in extra/*; do
        if [ -d "$dir" ]; then
            local basename
            basename=$(basename "$dir")
            if ! echo "$KEEP" | grep -qw "$basename"; then
                echo "  Removing $dir"
                rm -rf "$dir"
            fi
        fi
    done
    echo "✓ Bundled libraries cleaned"

    # Configure with CMake
    # -DINSTALL_* are relative to CMAKE_INSTALL_PREFIX
    cmake -S . -B build \
        -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
        -DCMAKE_PREFIX_PATH="${PREFIX}" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_FIND_FRAMEWORK=LAST \
        -DCMAKE_VERBOSE_MAKEFILE=ON \
        -DCOMPILATION_COMMENT=Fadogen \
        -DINSTALL_DOCDIR=share/doc/mysql \
        -DINSTALL_INCLUDEDIR=include/mysql \
        -DINSTALL_INFODIR=share/info \
        -DINSTALL_MANDIR=share/man \
        -DINSTALL_MYSQLSHAREDIR=share/mysql \
        -DINSTALL_PLUGINDIR=lib/plugin \
        -DMYSQL_DATADIR="${PREFIX}/data" \
        -DSYSCONFDIR="${PREFIX}/etc" \
        -DBISON_EXECUTABLE="${BISON_PATH}" \
        -DOPENSSL_ROOT_DIR="${PREFIX}" \
        -DWITH_ICU="${PREFIX}" \
        -DWITH_SYSTEM_LIBS=ON \
        -DWITH_EDITLINE=system \
        -DWITH_LZ4=system \
        -DWITH_PROTOBUF=system \
        -DWITH_SSL=system \
        -DWITH_ZLIB=system \
        -DWITH_ZSTD=system \
        -DWITH_UNIT_TESTS=OFF

    # Build
    cmake --build build --verbose -j"$(sysctl -n hw.ncpu)"

    # Install directly to final location
    cmake --install build

    # Remove the tests directory (as per Homebrew formula)
    rm -rf "${PREFIX}/mysql-test"

    echo "✓ ${PACKAGE_NAME} built successfully"
}
