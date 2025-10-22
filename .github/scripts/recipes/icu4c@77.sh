#!/bin/bash
# Build recipe for ICU4C 77.1
# Translated from: homebrew-core/Formula/i/icu4c@77.rb
# ICU = International Components for Unicode (C/C++ and Java libraries)

set -e

# Metadata
export PACKAGE_NAME="icu4c@77"
export PACKAGE_VERSION="77.1"
export PACKAGE_URL="https://github.com/unicode-org/icu/releases/download/release-77-1/icu4c-77_1-src.tgz"
export PACKAGE_SHA256="588e431f77327c39031ffbb8843c0e3bc122c211374485fa87dc5f3faff24061"

# No runtime dependencies (keg_only, self-contained)
export DEPENDENCIES=()

# Build function
build() {
    local PREFIX="$1"
    local SOURCE_DIR="$2"

    echo "Building icu4c@77 ${PACKAGE_VERSION}..."

    # ICU builds from the "source" subdirectory
    cd "${SOURCE_DIR}/source"

    # Add headerpad for install_name_tool (CRITICAL for relocation)
    export LDFLAGS="-Wl,-headerpad_max_install_names"

    # Configure arguments (from Homebrew formula)
    local args=(
        "--prefix=${PREFIX}"
        "--disable-samples"      # Don't build sample programs
        "--disable-tests"        # Don't build tests
        "--enable-static"        # Build static libraries
        "--with-library-bits=64" # 64-bit build
    )

    # Configure
    ./configure "${args[@]}"

    # Build (parallel)
    make -j"$(sysctl -n hw.ncpu)"

    # Install directly to final location
    make install

    echo "✓ icu4c@77 built successfully"
}
