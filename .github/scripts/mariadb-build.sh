#!/usr/bin/env bash
set -euo pipefail

# Usage: ./mariadb-build.sh 12.0.2
VERSION="$1"

# Validate version parameter
if [[ -z "$VERSION" ]]; then
    echo "[ERROR] Version parameter required"
    echo "[USAGE] $0 <version>  (e.g., $0 12.0.2)"
    exit 1
fi

# Validate version format (semantic versioning)
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "[ERROR] Invalid version format: $VERSION"
    echo "[USAGE] Use semantic versioning format: X.Y.Z (e.g., 12.0.2)"
    exit 1
fi

# Extract major version for version-specific configuration
MAJOR_VERSION=${VERSION%%.*}

WORKDIR="$HOME/fadogen-build/mariadb-$VERSION"
TEMP_DIR="/tmp/mariadb-$$"

# Cleanup function
cleanup() {
    rm -rf "$TEMP_DIR"
}

# Setup trap for cleanup
trap cleanup EXIT

# Setup workspace
mkdir -p "$WORKDIR" "$TEMP_DIR"
cd "$WORKDIR"

# Download and compile MariaDB from source
REPO_URL="https://github.com/MariaDB/server.git"
SOURCE_DIR="mariadb-server"
ARCHIVE="mariadb-$VERSION-macos-$(uname -m).tar.xz"

echo "[INFO] Downloading MariaDB $VERSION source code..."
rm -rf "${WORKDIR:?}/$SOURCE_DIR"
git clone --branch "mariadb-$VERSION" --depth 1 --recursive "$REPO_URL" "$WORKDIR/$SOURCE_DIR"

# Check if prebuilt OpenSSL is available
if [[ -n "${PREBUILT_OPENSSL_DIR:-}" ]] && [[ -d "$PREBUILT_OPENSSL_DIR" ]]; then
    echo "[INFO] Using prebuilt OpenSSL from: $PREBUILT_OPENSSL_DIR"
    OPENSSL_DIR="$PREBUILT_OPENSSL_DIR"
else
    echo "[INFO] Building static OpenSSL for portable binaries..."
    OPENSSL_DIR="$TEMP_DIR/openssl-static"
    cd "$TEMP_DIR"

    # Download OpenSSL 3.5.3 LTS
    curl -fsSL -o openssl-3.5.3.tar.gz https://www.openssl.org/source/openssl-3.5.3.tar.gz

    # Verify download succeeded
    if [[ ! -f openssl-3.5.3.tar.gz ]]; then
        echo "[ERROR] Failed to download OpenSSL"
        exit 1
    fi

    tar xzf openssl-3.5.3.tar.gz
    cd openssl-3.5.3

    # Configure for static build (optimized for speed)
    ./Configure darwin64-arm64-cc \
        --prefix="$OPENSSL_DIR" \
        --openssldir="$OPENSSL_DIR" \
        no-shared \
        no-tests \
        no-docs

    echo "[INFO] Compiling OpenSSL..."
    make

    echo "[INFO] Installing OpenSSL static libraries..."
    make install_sw
fi

echo "[INFO] Detecting macOS SDK..."
MACOS_SDK=$(xcrun --show-sdk-path)
echo "[INFO] Using SDK: $MACOS_SDK"

echo "[INFO] Building MariaDB $VERSION..."
cd "$WORKDIR/$SOURCE_DIR"

rm -rf build
mkdir build && cd build

# Common flags for both C and C++ (optimized for portable binaries)
COMMON_FLAGS="-w -fno-asynchronous-unwind-tables -fno-common -arch $(uname -m)"

# SSL configuration (version-dependent syntax)
if [[ "$MAJOR_VERSION" == "10" ]]; then
    # MariaDB 10: Use direct path (doesn't support OPENSSL keyword)
    SSL_CONFIG=(
        "-DWITH_SSL=$OPENSSL_DIR"
    )
else
    # MariaDB 11+: Use OPENSSL keyword with explicit root dir
    SSL_CONFIG=(
        "-DWITH_SSL=OPENSSL"
        "-DOPENSSL_ROOT_DIR=$OPENSSL_DIR"
        "-DOPENSSL_USE_STATIC_LIBS=TRUE"
    )
fi

echo "[INFO] Configuring MariaDB with CMake..."
PKG_CONFIG_EXECUTABLE=false cmake .. \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER=clang \
    -DCMAKE_CXX_COMPILER=clang++ \
    -DCMAKE_C_FLAGS="${COMMON_FLAGS}" \
    -DCMAKE_CXX_FLAGS="${COMMON_FLAGS}" \
    -DCMAKE_OSX_SYSROOT="${MACOS_SDK}" \
    -DBISON_EXECUTABLE=/opt/homebrew/opt/bison/bin/bison \
    -DCMAKE_DISABLE_FIND_PACKAGE_LZ4=TRUE \
    -DCMAKE_DISABLE_FIND_PACKAGE_ZSTD=TRUE \
    -DCMAKE_DISABLE_FIND_PACKAGE_LZO=TRUE \
    -DCMAKE_DISABLE_FIND_PACKAGE_Snappy=TRUE \
    -DCMAKE_DISABLE_FIND_PACKAGE_GnuTLS=TRUE \
    -DINSTALL_LAYOUT=STANDALONE \
    -DCPACK_MONOLITHIC_INSTALL=1 \
    "${SSL_CONFIG[@]}" \
    -DWITH_ZLIB=bundled \
    -DCONC_WITH_EXTERNAL_ZLIB=OFF \
    -DWITH_UNIT_TESTS=OFF \
    -DWITH_DEBUG=0 \
    -DMYSQL_MAINTAINER_MODE=OFF \
    -DWITHOUT_TOKUDB=1 \
    -DWITHOUT_ROCKSDB=1 \
    -DWITHOUT_MROONGA=1 \
    -DPLUGIN_PROVIDER_LZO=OFF \
    -DPLUGIN_PROVIDER_SNAPPY=OFF \
    -DPLUGIN_PROVIDER_LZ4=OFF \
    -DPLUGIN_PROVIDER_ZSTD=OFF \
    -DPLUGIN_ZSTD=OFF \
    -DCONNECT_WITH_MONGO=OFF \
    -DCONNECT_WITH_BSON=OFF \
    -DCONNECT_WITH_ODBC=OFF \
    -G Ninja

echo "[INFO] Compiling MariaDB (this may take a while)..."
cmake --build .

echo "[INFO] Creating portable tarball..."
cpack -G TXZ
mv ./mariadb-*.tar.xz "$WORKDIR/$ARCHIVE"

echo "[SUCCESS] Created: $ARCHIVE ($(du -sh "$WORKDIR/$ARCHIVE" | cut -f1))"
echo "[INFO] Archive location: $WORKDIR/$ARCHIVE"
echo "[INFO] MariaDB $VERSION ready for distribution"
