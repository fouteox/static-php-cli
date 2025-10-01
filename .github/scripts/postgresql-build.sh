#!/usr/bin/env bash
set -euo pipefail

# Usage: ./postgresql-build.sh 17.6
VERSION="$1"

# Validate version parameter
if [[ -z "$VERSION" ]]; then
    echo "[ERROR] Version parameter required"
    echo "[USAGE] $0 <version>  (e.g., $0 17.6)"
    exit 1
fi

# Validate version format (semantic versioning)
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+$ ]]; then
    echo "[ERROR] Invalid version format: $VERSION"
    echo "[USAGE] Use semantic versioning format: X.Y (e.g., 17.6)"
    exit 1
fi

WORKDIR="$HOME/fadogen-build/postgresql-$VERSION"
TEMP_DIR="/tmp/postgresql-$$"
INSTALL_DIR="$TEMP_DIR/install"

# Cleanup function
cleanup() {
    rm -rf "$TEMP_DIR"
}

# Setup trap for cleanup
trap cleanup EXIT

# Setup workspace
mkdir -p "$WORKDIR" "$TEMP_DIR" "$INSTALL_DIR"
cd "$WORKDIR"

# Download and compile PostgreSQL from source
REPO_URL="https://github.com/postgres/postgres.git"
SOURCE_DIR="postgresql-server"
ARCHIVE="postgresql-$VERSION-macos-$(uname -m).tar.xz"

# Convert version to PostgreSQL tag format (e.g., 17.6 -> REL_17_6)
PG_TAG="REL_${VERSION//./_}"

echo "[INFO] Downloading PostgreSQL $VERSION source code..."
rm -rf "${WORKDIR:?}/$SOURCE_DIR"
git clone --branch "$PG_TAG" --depth 1 "$REPO_URL" "$WORKDIR/$SOURCE_DIR"

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

echo "[INFO] Building PostgreSQL $VERSION..."
cd "$WORKDIR/$SOURCE_DIR"

# Common flags for both C and C++ (optimized for portable binaries)
COMMON_FLAGS="-O2 -fno-asynchronous-unwind-tables -arch $(uname -m)"

echo "[INFO] Configuring PostgreSQL..."
./configure \
    --prefix="$INSTALL_DIR" \
    --with-openssl \
    --with-libedit-preferred \
    --without-icu \
    --without-ldap \
    --without-gssapi \
    --disable-rpath \
    CFLAGS="${COMMON_FLAGS}" \
    CXXFLAGS="${COMMON_FLAGS}" \
    LDFLAGS="-L${OPENSSL_DIR}/lib" \
    CPPFLAGS="-I${OPENSSL_DIR}/include"

echo "[INFO] Compiling PostgreSQL (this may take a while)..."
make

echo "[INFO] Installing PostgreSQL to temporary directory..."
make install

echo "[INFO] Fixing library paths for portability..."
cd "$INSTALL_DIR"

# Bundle OpenSSL dylibs for portability
echo "[INFO] Bundling OpenSSL shared libraries..."
cp "$OPENSSL_DIR/lib/libssl.3.dylib" lib/
cp "$OPENSSL_DIR/lib/libcrypto.3.dylib" lib/
echo "[INFO] Copied libssl.3.dylib and libcrypto.3.dylib"

# Fix OpenSSL dylib install_names
install_name_tool -id "@loader_path/libssl.3.dylib" lib/libssl.3.dylib
install_name_tool -id "@loader_path/libcrypto.3.dylib" lib/libcrypto.3.dylib

# Fix libssl dependency on libcrypto
install_name_tool -change "$OPENSSL_DIR/lib/libcrypto.3.dylib" "@loader_path/libcrypto.3.dylib" lib/libssl.3.dylib

# Fix libpq install_name
if [[ -f lib/libpq.5.dylib ]]; then
    install_name_tool -id "@loader_path/libpq.5.dylib" lib/libpq.5.dylib
fi

# Fix OpenSSL library paths for portability
echo "[INFO] Fixing library dependencies for portability..."

# Store the hardcoded paths that PostgreSQL binaries were compiled with
OLD_SSL_PATH="$OPENSSL_DIR/lib/libssl.3.dylib"
OLD_CRYPTO_PATH="$OPENSSL_DIR/lib/libcrypto.3.dylib"
OLD_PQ_PATH="$INSTALL_DIR/lib/libpq.5.dylib"

# Step 1: Fix all dylibs in lib/ directory (including subdirectories)
echo "[INFO] Fixing dependencies in lib/ recursively..."
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

    # Change absolute paths to relative paths
    install_name_tool -change "$OLD_SSL_PATH" "$PREFIX/libssl.3.dylib" "$file" 2>/dev/null || true
    install_name_tool -change "$OLD_CRYPTO_PATH" "$PREFIX/libcrypto.3.dylib" "$file" 2>/dev/null || true
    install_name_tool -change "$OLD_PQ_PATH" "$PREFIX/libpq.5.dylib" "$file" 2>/dev/null || true
done

# Step 2: Fix all binaries in bin/ directory
echo "[INFO] Fixing dependencies in bin/*..."
for file in bin/*; do
    [[ -f "$file" ]] || continue
    # Change absolute paths to relative paths (errors ignored for scripts)
    install_name_tool -change "$OLD_SSL_PATH" "@loader_path/../lib/libssl.3.dylib" "$file" 2>/dev/null || true
    install_name_tool -change "$OLD_CRYPTO_PATH" "@loader_path/../lib/libcrypto.3.dylib" "$file" 2>/dev/null || true
    install_name_tool -change "$OLD_PQ_PATH" "@loader_path/../lib/libpq.5.dylib" "$file" 2>/dev/null || true
done

echo "[INFO] Library path fixing completed"

echo "[INFO] Creating portable tarball..."
tar -cJf "$WORKDIR/$ARCHIVE" .

echo "[SUCCESS] Created: $ARCHIVE ($(du -sh "$WORKDIR/$ARCHIVE" | cut -f1))"
echo "[INFO] Archive location: $WORKDIR/$ARCHIVE"
echo "[INFO] PostgreSQL $VERSION ready for distribution"