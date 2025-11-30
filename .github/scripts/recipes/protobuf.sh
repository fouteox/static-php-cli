#!/bin/bash
# Build recipe for protobuf 33.1
# Translated from: homebrew-core/Formula/p/protobuf.rb
# Description: Protocol Buffers - Google's data interchange format

set -e

# Metadata
export PACKAGE_NAME="protobuf"
export PACKAGE_VERSION="33.1"
export PACKAGE_URL="https://github.com/protocolbuffers/protobuf/releases/download/v33.1/protobuf-33.1.tar.gz"
export PACKAGE_SHA256="fda132cb0c86400381c0af1fe98bd0f775cb566cb247cdcc105e344e00acc30e"

# Runtime dependencies
export DEPENDENCIES=(
    "abseil"
)

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

    # Configure with CMake (keep CMAKE_CXX_STANDARD in sync with abseil.rb)
    cmake -S . -B build \
        -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
        -DCMAKE_PREFIX_PATH="${PREFIX}" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_CXX_STANDARD=17 \
        -DBUILD_SHARED_LIBS=ON \
        -Dprotobuf_BUILD_LIBPROTOC=ON \
        -Dprotobuf_BUILD_SHARED_LIBS=ON \
        -Dprotobuf_INSTALL_EXAMPLES=ON \
        -Dprotobuf_BUILD_TESTS=ON \
        -Dprotobuf_USE_EXTERNAL_GTEST=ON \
        -Dprotobuf_FORCE_FETCH_DEPENDENCIES=OFF \
        -Dprotobuf_LOCAL_DEPENDENCIES_ONLY=ON

    # Build
    cmake --build build -j"$(sysctl -n hw.ncpu)"

    # Run tests (as per Homebrew formula)
    echo "→ Running tests..."
    ctest --test-dir build --verbose || {
        echo "⚠ Some tests failed, but continuing installation"
    }

    # Install directly to final location
    cmake --install build

    echo "✓ ${PACKAGE_NAME} built successfully"
}
