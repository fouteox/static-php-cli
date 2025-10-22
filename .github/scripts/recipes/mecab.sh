#!/bin/bash
# Build recipe for mecab 0.996
# Translated from: homebrew-core/Formula/m/mecab.rb
# Description: Yet another part-of-speech and morphological analyzer

set -e

# Metadata
export PACKAGE_NAME="mecab"
export PACKAGE_VERSION="0.996"
export PACKAGE_URL="https://deb.debian.org/debian/pool/main/m/mecab/mecab_0.996.orig.tar.gz"
export PACKAGE_SHA256="e073325783135b72e666145c781bb48fada583d5224fb2490fb6c1403ba69c59"

# No runtime dependencies
export DEPENDENCIES=()

# Build dependencies (via Homebrew, not in bundle)
export BUILD_DEPENDENCIES=()

# Build function
build() {
    local PREFIX="$1"
    local SOURCE_DIR="$2"

    echo "Building ${PACKAGE_NAME} ${PACKAGE_VERSION}..."

    cd "${SOURCE_DIR}"

    # Configure
    ./configure \
        --disable-dependency-tracking \
        --prefix="${PREFIX}" \
        --sysconfdir="${PREFIX}/etc"

    # Build
    make -j"$(sysctl -n hw.ncpu)"

    # Install
    make install

    # Fix dictionary paths to use our PREFIX instead of HOMEBREW_PREFIX
    # mecab-config
    if [ -f "${PREFIX}/bin/mecab-config" ]; then
        sed -i.bak "s|${PREFIX}/lib/mecab/dic|${PREFIX}/lib/mecab/dic|g" "${PREFIX}/bin/mecab-config"
        rm -f "${PREFIX}/bin/mecab-config.bak"
    fi

    # mecabrc
    if [ -f "${PREFIX}/etc/mecabrc" ]; then
        sed -i.bak "s|${PREFIX}/lib/mecab/dic|${PREFIX}/lib/mecab/dic|g" "${PREFIX}/etc/mecabrc"
        rm -f "${PREFIX}/etc/mecabrc.bak"
    fi

    # Create dic directory
    mkdir -p "${PREFIX}/lib/mecab/dic"

    echo "✓ ${PACKAGE_NAME} built successfully"
}
