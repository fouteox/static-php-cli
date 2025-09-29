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

echo "[INFO] Detecting macOS SDK..."
MACOS_SDK=$(xcrun --show-sdk-path)
echo "[INFO] Using SDK: $MACOS_SDK"

echo "[INFO] Building MariaDB $VERSION..."
cd "$WORKDIR/$SOURCE_DIR"

rm -rf build
mkdir build && cd build

# Common flags for both C and C++ (optimized for portable binaries)
COMMON_FLAGS="-w -fno-asynchronous-unwind-tables -fno-common -arch $(uname -m)"

echo "[INFO] Configuring MariaDB with CMake..."
cmake .. \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER=clang \
    -DCMAKE_CXX_COMPILER=clang++ \
    -DCMAKE_C_FLAGS="${COMMON_FLAGS}" \
    -DCMAKE_CXX_FLAGS="${COMMON_FLAGS}" \
    -DCMAKE_OSX_SYSROOT="${MACOS_SDK}" \
    -DBISON_EXECUTABLE=/opt/homebrew/opt/bison/bin/bison \
    -DINSTALL_LAYOUT=STANDALONE \
    -DCPACK_MONOLITHIC_INSTALL=1 \
    -DWITH_SSL=bundled \
    -DWITH_ZLIB=bundled \
    -DCONC_WITH_EXTERNAL_ZLIB=OFF \
    -DWITH_UNIT_TESTS=OFF \
    -DWITH_DEBUG=0 \
    -DMYSQL_MAINTAINER_MODE=OFF \
    -DWITHOUT_TOKUDB=1 \
    -DWITHOUT_ROCKSDB=1 \
    -DWITHOUT_MROONGA=1 \
    -DPLUGIN_TOKUDB=NO \
    -DPLUGIN_ROCKSDB=NO \
    -DPLUGIN_MROONGA=NO \
    -DPLUGIN_PROVIDER_LZO=NO \
    -DPLUGIN_PROVIDER_SNAPPY=NO \
    -DPLUGIN_PROVIDER_LZ4=NO \
    -DPLUGIN_PROVIDER_ZSTD=NO \
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
