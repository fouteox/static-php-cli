#!/bin/bash
# Build recipe for msgpack 6.1.0
# Translated from: homebrew-core/Formula/m/msgpack.rb
# Description: Library for a binary-based efficient data interchange format

set -e

# Metadata
export PACKAGE_NAME="msgpack"
export PACKAGE_VERSION="6.1.0"
export PACKAGE_URL="https://github.com/msgpack/msgpack-c/releases/download/c-6.1.0/msgpack-c-6.1.0.tar.gz"
export PACKAGE_SHA256="674119f1a85b5f2ecc4c7d5c2859edf50c0b05e0c10aa0df85eefa2c8c14b796"

# No runtime dependencies
export DEPENDENCIES=()

# Build dependencies (via Homebrew, not in bundle)
export BUILD_DEPENDENCIES=(
    "cmake"
)

# Build function
build() {
    local PREFIX="$1"
    local SOURCE_DIR="$2"

    echo "Building ${PACKAGE_NAME} ${PACKAGE_VERSION}..."

    cd "${SOURCE_DIR}"

    # Configure with CMake
    cmake -S . -B build \
        -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_FIND_FRAMEWORK=LAST \
        -DMSGPACK_BUILD_TESTS=OFF

    # Build
    cmake --build build -j"$(sysctl -n hw.ncpu)"

    # Install
    cmake --install build

    # Create compatibility symlinks (libmsgpackc -> libmsgpack-c)
    # This maintains compatibility with older software expecting libmsgpackc
    cd "${PREFIX}/lib"
    for dylib in libmsgpack-c*.dylib; do
        if [ -f "$dylib" ]; then
            local old_name="${dylib//msgpack-c/msgpackc}"
            ln -sf "$dylib" "$old_name"
        fi
    done

    echo "✓ ${PACKAGE_NAME} built successfully"
}
