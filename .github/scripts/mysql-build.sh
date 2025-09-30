#!/usr/bin/env bash
set -euo pipefail

# Usage: ./mysql-build.sh 8.4.3
VERSION="$1"

# Validate version parameter
if [[ -z "$VERSION" ]]; then
    echo "[ERROR] Version parameter required"
    echo "[USAGE] $0 <version>  (e.g., $0 8.4.3)"
    exit 1
fi

# Validate version format (semantic versioning)
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "[ERROR] Invalid version format: $VERSION"
    echo "[USAGE] Use semantic versioning format: X.Y.Z (e.g., 8.4.3)"
    exit 1
fi

WORKDIR="$HOME/fadogen-build/mysql-$VERSION"
TEMP_DIR="/tmp/mysql-$$"

# Cleanup function
cleanup() {
    rm -rf "$TEMP_DIR"
}

# Setup trap for cleanup
trap cleanup EXIT

# Setup workspace
mkdir -p "$WORKDIR" "$TEMP_DIR"
cd "$WORKDIR"

# Download and compile MySQL from source
REPO_URL="https://github.com/mysql/mysql-server.git"
SOURCE_DIR="mysql-server"
ARCHIVE="mysql-$VERSION-macos-$(uname -m).tar.xz"

echo "[INFO] Downloading MySQL $VERSION source code..."
rm -rf "${WORKDIR:?}/$SOURCE_DIR"
git clone --branch "mysql-$VERSION" --depth 1 --recursive "$REPO_URL" "$WORKDIR/$SOURCE_DIR"

# Check if prebuilt OpenSSL is available
if [[ -n "${PREBUILT_OPENSSL_DIR:-}" ]] && [[ -d "$PREBUILT_OPENSSL_DIR" ]]; then
    echo "[INFO] Using prebuilt OpenSSL from: $PREBUILT_OPENSSL_DIR"
    OPENSSL_DIR="$PREBUILT_OPENSSL_DIR"
else
    # Use persistent OpenSSL path (not temp directory)
    OPENSSL_DIR="$HOME/fadogen-build/openssl-static"

    # Check if OpenSSL is already built
    if [[ ! -d "$OPENSSL_DIR/lib" ]]; then
        echo "[INFO] Building OpenSSL for portable binaries..."
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

        # Configure for shared build (creates both .a and .dylib)
        ./Configure darwin64-arm64-cc \
            --prefix="$OPENSSL_DIR" \
            --openssldir="$OPENSSL_DIR" \
            shared \
            no-tests \
            no-docs \
            no-atexit

        echo "[INFO] Compiling OpenSSL..."
        make

        echo "[INFO] Installing OpenSSL libraries..."
        make install_sw
    else
        echo "[INFO] Using existing OpenSSL from: $OPENSSL_DIR"
    fi
fi

echo "[INFO] Detecting macOS SDK..."
MACOS_SDK=$(xcrun --show-sdk-path)
echo "[INFO] Using SDK: $MACOS_SDK"

echo "[INFO] Building MySQL $VERSION..."
cd "$WORKDIR/$SOURCE_DIR"

rm -rf build
mkdir build && cd build

# Common flags for both C and C++ (optimized for portable binaries)
COMMON_FLAGS="-fno-asynchronous-unwind-tables -arch $(uname -m)"

echo "[INFO] Configuring MySQL with CMake..."
PKG_CONFIG_EXECUTABLE=false cmake .. \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER=clang \
    -DCMAKE_CXX_COMPILER=clang++ \
    -DCMAKE_C_FLAGS="${COMMON_FLAGS}" \
    -DCMAKE_CXX_FLAGS="${COMMON_FLAGS}" \
    -DCMAKE_OSX_SYSROOT="${MACOS_SDK}" \
    -DBISON_EXECUTABLE=/opt/homebrew/opt/bison/bin/bison \
    -DCMAKE_PREFIX_PATH="$OPENSSL_DIR" \
    -DOPENSSL_ROOT_DIR="$OPENSSL_DIR" \
    -DWITH_SSL=system \
    -DWITH_ZLIB=bundled \
    -DWITH_FIDO=none \
    -DWITH_MYSQLX=OFF \
    -DINSTALL_MYSQLTESTDIR="" \
    -DMYSQL_MAINTAINER_MODE=OFF \
    -DCPACK_MONOLITHIC_INSTALL=1 \
    -G Ninja

echo "[INFO] Compiling MySQL (this may take a while)..."
cmake --build .

echo "[INFO] Installing MySQL to temporary directory..."
INSTALL_DIR="$TEMP_DIR/mysql-install"
cmake --install . --prefix "$INSTALL_DIR"

echo "[INFO] Bundling OpenSSL for portability..."
cd "$INSTALL_DIR"

# Bundle only the 2 OpenSSL dylibs
cp "$OPENSSL_DIR/lib/libssl.3.dylib" lib/
cp "$OPENSSL_DIR/lib/libcrypto.3.dylib" lib/

# Fix OpenSSL dylib install_names
install_name_tool -id "@loader_path/libssl.3.dylib" lib/libssl.3.dylib
install_name_tool -id "@loader_path/libcrypto.3.dylib" lib/libcrypto.3.dylib

# Fix libssl dependency on libcrypto
install_name_tool -change "$OPENSSL_DIR/lib/libcrypto.3.dylib" "@loader_path/libcrypto.3.dylib" lib/libssl.3.dylib

# Fix OpenSSL dependencies in all MySQL binaries and libraries
OLD_SSL="$OPENSSL_DIR/lib/libssl.3.dylib"
OLD_CRYPTO="$OPENSSL_DIR/lib/libcrypto.3.dylib"

# Fix all dylibs and plugins in lib/ (including subdirectories)
find lib -type f \( -name "*.dylib" -o -name "*.so" \) | while read -r file; do
    DEPTH=$(echo "$file" | awk -F'/' '{print NF-2}')
    if [[ $DEPTH -eq 0 ]]; then
        PREFIX="@loader_path"
    else
        PREFIX="@loader_path"
        for ((i=0; i<DEPTH; i++)); do
            PREFIX="$PREFIX/.."
        done
    fi

    install_name_tool -change "$OLD_SSL" "$PREFIX/libssl.3.dylib" "$file" 2>/dev/null || true
    install_name_tool -change "$OLD_CRYPTO" "$PREFIX/libcrypto.3.dylib" "$file" 2>/dev/null || true
done

# Fix all binaries
for file in bin/*; do
    [[ -f "$file" ]] || continue
    install_name_tool -change "$OLD_SSL" "@loader_path/../lib/libssl.3.dylib" "$file" 2>/dev/null || true
    install_name_tool -change "$OLD_CRYPTO" "@loader_path/../lib/libcrypto.3.dylib" "$file" 2>/dev/null || true
done

echo "[INFO] Creating portable tarball..."
tar -cJf "$WORKDIR/$ARCHIVE" .

echo "[SUCCESS] Created: $ARCHIVE ($(du -sh "$WORKDIR/$ARCHIVE" | cut -f1))"
echo "[INFO] Archive location: $WORKDIR/$ARCHIVE"
echo "[INFO] MySQL $VERSION ready for distribution"
