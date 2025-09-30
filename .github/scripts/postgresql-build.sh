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
        echo "[INFO] Building static OpenSSL for portable binaries..."
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

        # Configure for static build
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

# Fix libpq install_name to use @rpath
if [[ -f lib/libpq.5.dylib ]]; then
    install_name_tool -id "@rpath/libpq.5.dylib" lib/libpq.5.dylib
    echo "[INFO] Fixed libpq.5.dylib install name"
fi

# Fix all binaries that depend on libpq to use relative path
for binary in bin/*; do
    if [[ -f "$binary" ]] && [[ -x "$binary" ]]; then
        # Check if binary depends on libpq
        if otool -L "$binary" 2>/dev/null | grep -q "libpq"; then
            # Get the current libpq path
            OLD_PATH=$(otool -L "$binary" | grep libpq | awk '{print $1}' | head -1)
            if [[ -n "$OLD_PATH" ]]; then
                # Change to relative path using @executable_path
                install_name_tool -change "$OLD_PATH" "@executable_path/../lib/libpq.5.dylib" "$binary"
                # Add rpath pointing to lib directory
                install_name_tool -add_rpath "@executable_path/../lib" "$binary" 2>/dev/null || true
                echo "[INFO] Fixed $(basename "$binary")"
            fi
        fi
    fi
done

echo "[INFO] Creating portable tarball..."
tar -cJf "$WORKDIR/$ARCHIVE" .

echo "[SUCCESS] Created: $ARCHIVE ($(du -sh "$WORKDIR/$ARCHIVE" | cut -f1))"
echo "[INFO] Archive location: $WORKDIR/$ARCHIVE"
echo "[INFO] PostgreSQL $VERSION ready for distribution"