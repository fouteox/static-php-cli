#!/bin/bash
# Build recipe for readline 8.3.1
# Translated from: homebrew-core/Formula/r/readline.rb
# Description: Library for command-line editing

set -e

# Metadata
export PACKAGE_NAME="readline"
export PACKAGE_VERSION="8.3.1"
export PACKAGE_URL="https://ftpmirror.gnu.org/gnu/readline/readline-8.3.tar.gz"
export PACKAGE_SHA256="fe5383204467828cd495ee8d1d3c037a7eba1389c22bc6a041f627976f9061cc"

# Runtime dependencies
export DEPENDENCIES=(
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

    # Apply patches (readline 8.3.1 = 8.3 + patch 001)
    echo "→ Applying patches..."
    local PATCH_URL="https://ftpmirror.gnu.org/gnu/readline/readline-8.3-patches/readline83-001"
    local PATCH_SHA256="21f0a03106dbe697337cd25c70eb0edbaa2bdb6d595b45f83285cdd35bac84de"
    local PATCH_FILE="${DOWNLOADS_DIR}/readline83-001"

    # Download patch
    if [ ! -f "$PATCH_FILE" ]; then
        curl -fSL -o "$PATCH_FILE" "$PATCH_URL"
    fi

    # Verify patch checksum
    echo "$PATCH_SHA256  $PATCH_FILE" | shasum -a 256 -c - || {
        echo "✗ Patch checksum verification failed"
        return 1
    }

    # Apply patch (-p0 means strip 0 path components)
    patch -p0 < "$PATCH_FILE"
    echo "✓ Patches applied"

    # Configure with ncurses support
    ./configure \
        --prefix="${PREFIX}" \
        --with-curses

    # Build (with ncurses linking for shared library)
    make -j"$(sysctl -n hw.ncpu)" SHLIB_LIBS=-lcurses

    # Install directly to final location
    make install SHLIB_LIBS=-lcurses

    echo "✓ ${PACKAGE_NAME} built successfully"
}
