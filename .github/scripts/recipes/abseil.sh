#!/bin/bash
# Build recipe for abseil 20250814.1
# Translated from: homebrew-core/Formula/a/abseil.rb
# Description: C++ Common Libraries

set -e

# Metadata
export PACKAGE_NAME="abseil"
export PACKAGE_VERSION="20250814.1"
export PACKAGE_URL="https://github.com/abseil/abseil-cpp/archive/refs/tags/20250814.1.tar.gz"
export PACKAGE_SHA256="1692f77d1739bacf3f94337188b78583cf09bab7e420d2dc6c5605a4f86785a1"

# Runtime dependencies
export DEPENDENCIES=()

# Build dependencies (via Homebrew, not in bundle)
export BUILD_DEPENDENCIES=(
    "cmake"
    "googletest"
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
    cmake -S . -B build \
        -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_CXX_STANDARD=17 \
        -DBUILD_SHARED_LIBS=ON \
        -DABSL_PROPAGATE_CXX_STD=ON \
        -DABSL_ENABLE_INSTALL=ON \
        -DABSL_BUILD_TEST_HELPERS=ON \
        -DABSL_USE_EXTERNAL_GOOGLETEST=ON \
        -DABSL_FIND_GOOGLETEST=ON

    # Build
    cmake --build build -j"$(sysctl -n hw.ncpu)"

    # Install directly to final location
    cmake --install build

    echo "✓ ${PACKAGE_NAME} built successfully"
}
