#!/bin/bash
# Build recipe for gettext 0.26
# Translated from: homebrew-core/Formula/g/gettext.rb
# Description: GNU internationalization (i18n) and localization (l10n) library

set -e

# Metadata
export PACKAGE_NAME="gettext"
export PACKAGE_VERSION="0.26"
export PACKAGE_URL="https://ftpmirror.gnu.org/gnu/gettext/gettext-0.26.tar.gz"
export PACKAGE_SHA256="39acf4b0371e9b110b60005562aace5b3631fed9b1bb9ecccfc7f56e58bb1d7f"

# Runtime dependencies
export DEPENDENCIES=(
    "libunistring"
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

    # Workaround for newer Clang
    export CFLAGS="-Wno-incompatible-function-pointer-types"

    # macOS iconv workaround for Sequoia+
    export am_cv_func_iconv_works="yes"

    cd "${SOURCE_DIR}"

    # Configure
    ./configure \
        --prefix="${PREFIX}" \
        --with-libunistring-prefix="${PREFIX}" \
        --disable-silent-rules \
        --with-included-glib \
        --with-included-libcroco \
        --with-emacs \
        --disable-java \
        --disable-csharp \
        --without-git \
        --without-cvs \
        --without-xz \
        --with-included-gettext

    # Build (parallel)
    make -j"$(sysctl -n hw.ncpu)"

    # Install directly to final location (non-parallel as per Homebrew formula)
    make install

    echo "✓ ${PACKAGE_NAME} built successfully"
}
