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

echo "[INFO] Installing MariaDB to temporary directory..."
INSTALL_DIR="$TEMP_DIR/mariadb-install"
cmake --install . --prefix "$INSTALL_DIR"

echo "[INFO] Bundling OpenSSL for portability..."
cd "$INSTALL_DIR"

# Copy all OpenSSL content recursively into MariaDB directories
echo "[INFO] Copying OpenSSL binaries..."
cp -r "$OPENSSL_DIR/bin"/* bin/

echo "[INFO] Copying OpenSSL headers..."
cp -r "$OPENSSL_DIR/include"/* include/

echo "[INFO] Copying OpenSSL libraries..."
cp -r "$OPENSSL_DIR/lib"/* lib/

# Fix OpenSSL library paths for portability
# MariaDB ignores CMAKE_INSTALL_RPATH, so we must fix dylib paths post-build
echo "[INFO] Fixing OpenSSL library paths for portability..."

# Store the hardcoded paths that MariaDB binaries were compiled with
OLD_SSL_PATH="$OPENSSL_DIR/lib/libssl.3.dylib"
OLD_CRYPTO_PATH="$OPENSSL_DIR/lib/libcrypto.3.dylib"

# Step 1: Fix OpenSSL dylib install names and internal dependencies
echo "[INFO] Fixing OpenSSL dylib install_names..."
install_name_tool -id "@loader_path/libssl.3.dylib" lib/libssl.3.dylib
install_name_tool -id "@loader_path/libcrypto.3.dylib" lib/libcrypto.3.dylib
install_name_tool -change "$OLD_CRYPTO_PATH" "@loader_path/libcrypto.3.dylib" lib/libssl.3.dylib

# Step 2: Fix all dylibs and plugins in lib/ directory (including subdirectories)
echo "[INFO] Fixing OpenSSL dependencies in lib/ recursively..."
find lib -type f \( -name "*.dylib" -o -name "*.so" \) | while read -r file; do
    # Calculate the relative path from file location to lib/ root
    # For files in lib/ -> @loader_path
    # For files in lib/subdir/ -> @loader_path/..
    # For files in lib/subdir/subdir2/ -> @loader_path/../..
    DEPTH=$(echo "$file" | awk -F'/' '{print NF-2}')
    if [[ $DEPTH -eq 0 ]]; then
        PREFIX="@loader_path"
    else
        PREFIX="@loader_path"
        for ((i=0; i<DEPTH; i++)); do
            PREFIX="$PREFIX/.."
        done
    fi

    # Fix install_name for dylibs (not .so files)
    if [[ "$file" == *.dylib ]]; then
        BASENAME=$(basename "$file")
        install_name_tool -id "$PREFIX/$BASENAME" "$file" 2>/dev/null || true
    fi

    # Change absolute OpenSSL paths to relative paths
    install_name_tool -change "$OLD_SSL_PATH" "$PREFIX/libssl.3.dylib" "$file" 2>/dev/null || true
    install_name_tool -change "$OLD_CRYPTO_PATH" "$PREFIX/libcrypto.3.dylib" "$file" 2>/dev/null || true
done

# Step 3: Fix all binaries in bin/ directory
echo "[INFO] Fixing OpenSSL dependencies in bin/*..."
for file in bin/*; do
    [[ -f "$file" ]] || continue
    # Change absolute paths to relative @loader_path/../lib (errors ignored for scripts like c_rehash)
    install_name_tool -change "$OLD_SSL_PATH" "@loader_path/../lib/libssl.3.dylib" "$file" 2>/dev/null || true
    install_name_tool -change "$OLD_CRYPTO_PATH" "@loader_path/../lib/libcrypto.3.dylib" "$file" 2>/dev/null || true
done

echo "[INFO] OpenSSL bundling completed"

echo "[INFO] Creating portable tarball..."
tar -cJf "$WORKDIR/$ARCHIVE" .

echo "[SUCCESS] Created: $ARCHIVE ($(du -sh "$WORKDIR/$ARCHIVE" | cut -f1))"
echo "[INFO] Archive location: $WORKDIR/$ARCHIVE"
echo "[INFO] MariaDB $VERSION ready for distribution"
