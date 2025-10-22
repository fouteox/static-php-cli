#!/bin/bash
# Build recipe for zstd 1.5.7
# Translated from: homebrew-core/Formula/z/zstd.rb
# Description: Zstandard is a real-time compression algorithm

set -e

# Metadata
export PACKAGE_NAME="zstd"
export PACKAGE_VERSION="1.5.7"
export PACKAGE_URL="https://github.com/facebook/zstd/archive/refs/tags/v1.5.7.tar.gz"
export PACKAGE_SHA256="37d7284556b20954e56e1ca85b80226768902e2edabd3b649e9e72c0c9012ee3"

# Runtime dependencies
export DEPENDENCIES=(
    "lz4"
    "xz"
    "zlib"
)

# Build dependencies (via Homebrew, not in bundle)
export BUILD_DEPENDENCIES=(
    "cmake"
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

    # Configure with CMake
    cmake -S build/cmake -B builddir \
        -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_SHARED_LIBS=ON \
        -DZSTD_PROGRAMS_LINK_SHARED=ON \
        -DZSTD_BUILD_CONTRIB=ON \
        -DZSTD_LEGACY_SUPPORT=ON \
        -DZSTD_ZLIB_SUPPORT=ON \
        -DZSTD_LZMA_SUPPORT=ON \
        -DZSTD_LZ4_SUPPORT=ON \
        -DCMAKE_CXX_STANDARD=11

    # Build
    cmake --build builddir -j"$(sysctl -n hw.ncpu)"

    # Install directly to final location
    cmake --install builddir

    # Fix pkgconfig file to use correct prefix
    local PC_FILE="${PREFIX}/lib/pkgconfig/libzstd.pc"
    if [ -f "$PC_FILE" ]; then
        sed -i '' "s|^prefix=.*|prefix=${PREFIX}|" "$PC_FILE"
    fi

    echo "✓ ${PACKAGE_NAME} built successfully"
}
