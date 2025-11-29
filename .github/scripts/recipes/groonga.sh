#!/bin/bash
# Build recipe for groonga 15.2.0
# Translated from: homebrew-core/Formula/g/groonga.rb
# Description: Fulltext search engine and column store

set -e

# Metadata
export PACKAGE_NAME="groonga"
export PACKAGE_VERSION="15.2.0"
export PACKAGE_URL="https://github.com/groonga/groonga/releases/download/v15.2.0/groonga-15.2.0.tar.gz"
export PACKAGE_SHA256="068a5cb0b32352e0c04f1a5a800259ea5bb740800add7c9b786d052e16da7ad9"

# Runtime dependencies
export DEPENDENCIES=(
    "mecab"
    "mecab-ipadic"
    "msgpack"
    "openssl@3"
    "zlib"
)

# Build dependencies (via Homebrew, not in bundle)
export BUILD_DEPENDENCIES=(
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
    export LDFLAGS="-L${PREFIX}/lib -Wl,-headerpad_max_install_names"
    export CPPFLAGS="-I${PREFIX}/include"
    # Force zlib from our bundle
    export ZLIB_CFLAGS="-I${PREFIX}/include"
    export ZLIB_LIBS="-L${PREFIX}/lib -lz"

    cd "${SOURCE_DIR}"

    # Configure in a build directory
    mkdir -p builddir
    cd builddir

    ../configure \
        --disable-dependency-tracking \
        --prefix="${PREFIX}" \
        --disable-zeromq \
        --disable-apache-arrow \
        --with-luajit=no \
        --with-ssl \
        --with-zlib="${PREFIX}" \
        --without-libstemmer \
        --with-mecab

    # Build
    make -j"$(sysctl -n hw.ncpu)"

    # Install
    make install

    # Build and install groonga-normalizer-mysql resource
    echo "→ Building groonga-normalizer-mysql..."
    cd "${SOURCE_DIR}"
    local NORMALIZER_DIR="groonga-normalizer-mysql-1.2.9"
    curl -L "https://github.com/groonga/groonga-normalizer-mysql/releases/download/v1.2.9/groonga-normalizer-mysql-1.2.9.tar.gz" \
        | tar xz

    cd "${NORMALIZER_DIR}"

    # Ensure groonga tools are in PATH and PKG_CONFIG_PATH is set
    export PATH="${PREFIX}/bin:${PATH}"
    export PKG_CONFIG_PATH="${PREFIX}/lib/pkgconfig"

    cmake -S . -B _build \
        -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_FIND_FRAMEWORK=LAST

    cmake --build _build -j"$(sysctl -n hw.ncpu)"
    cmake --install _build

    echo "✓ ${PACKAGE_NAME} built successfully"
}
