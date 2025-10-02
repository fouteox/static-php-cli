#!/usr/bin/env bash
set -euo pipefail

# ================================
# UNIFIED DATABASE BUILD SCRIPT
# ================================
# Builds MySQL, PostgreSQL, MariaDB, Redis, or Valkey from source with bundled OpenSSL
# Usage: ./database-build.sh <service> <version>
# Examples:
#   ./database-build.sh mysql 8.4.3
#   ./database-build.sh postgresql 17.6
#   ./database-build.sh mariadb 12.0.2
#   ./database-build.sh redis 7.4.5
#   ./database-build.sh valkey 8.0.5

# ================================
# COMMON FUNCTIONS
# ================================

validate_version() {
    local service="$1"
    local version="$2"

    if [[ -z "$version" ]]; then
        echo "[ERROR] Version parameter required"
        echo "[USAGE] $0 <service> <version>"
        exit 1
    fi

    case "$service" in
        postgresql)
            if ! [[ "$version" =~ ^[0-9]+\.[0-9]+$ ]]; then
                echo "[ERROR] Invalid version format for PostgreSQL: $version"
                echo "[USAGE] PostgreSQL version must be X.Y (e.g., 17.6)"
                exit 1
            fi
            ;;
        mysql|mariadb|redis|valkey)
            if ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                echo "[ERROR] Invalid version format for $service: $version"
                echo "[USAGE] $service version must be X.Y.Z (e.g., 8.4.3 for MySQL, 7.4.5 for Redis)"
                exit 1
            fi
            ;;
    esac
}

setup_workspace() {
    local service="$1"
    local version="$2"

    WORKDIR="$HOME/fadogen-build/${service}-${version}"
    TEMP_DIR="/tmp/${service}-$$"
    SOURCE_DIR="${service}-server"
    ARCHIVE="${service}-${version}-macos-$(uname -m).tar.xz"

    # Cleanup function
    cleanup() {
        rm -rf "$TEMP_DIR"
    }

    # Setup trap for cleanup
    trap cleanup EXIT

    # Setup workspace
    mkdir -p "$WORKDIR" "$TEMP_DIR"
    cd "$WORKDIR"

    echo "[INFO] Workspace: $WORKDIR"
    echo "[INFO] Temp dir: $TEMP_DIR"
}

setup_openssl() {
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

    export OPENSSL_DIR
}

detect_macos_sdk() {
    echo "[INFO] Detecting macOS SDK..."
    MACOS_SDK=$(xcrun --show-sdk-path)
    echo "[INFO] Using SDK: $MACOS_SDK"
    export MACOS_SDK
}

git_clone_source() {
    local service="$1"
    local version="$2"

    local tag repo recursive

    case "$service" in
        mysql)
            tag="mysql-$version"
            repo="https://github.com/mysql/mysql-server.git"
            recursive=""
            ;;
        postgresql)
            tag="REL_${version//./_}"
            repo="https://github.com/postgres/postgres.git"
            recursive=""
            ;;
        mariadb)
            tag="mariadb-$version"
            repo="https://github.com/MariaDB/server.git"
            recursive="--recursive"
            ;;
        redis)
            tag="$version"
            repo="https://github.com/redis/redis.git"
            recursive=""
            ;;
        valkey)
            tag="$version"
            repo="https://github.com/valkey-io/valkey.git"
            recursive=""
            ;;
    esac

    echo "[INFO] Downloading $service $version source code..."
    rm -rf "${WORKDIR:?}/$SOURCE_DIR"
    git clone --branch "$tag" --depth 1 $recursive "$repo" "$WORKDIR/$SOURCE_DIR"
}

bundle_openssl() {
    local service="$1"

    echo "[INFO] Bundling OpenSSL for portability..."
    cd "$INSTALL_DIR"

    if [[ "$service" == "mariadb" ]]; then
        # Full bundling for MariaDB
        echo "[INFO] Copying OpenSSL binaries..."
        cp -r "$OPENSSL_DIR/bin"/* bin/

        echo "[INFO] Copying OpenSSL headers..."
        cp -r "$OPENSSL_DIR/include"/* include/

        echo "[INFO] Copying OpenSSL libraries..."
        cp -r "$OPENSSL_DIR/lib"/* lib/

        # Fix OpenSSL dylib install_names in lib/
        install_name_tool -id "@loader_path/libssl.3.dylib" lib/libssl.3.dylib
        install_name_tool -id "@loader_path/libcrypto.3.dylib" lib/libcrypto.3.dylib
        install_name_tool -change "$OPENSSL_DIR/lib/libcrypto.3.dylib" "@loader_path/libcrypto.3.dylib" lib/libssl.3.dylib
    elif [[ "$service" == "redis" || "$service" == "valkey" ]]; then
        # Redis/Valkey: everything in bin/ directory
        echo "[INFO] Bundling OpenSSL directly in bin/..."
        cp "$OPENSSL_DIR/lib/libssl.3.dylib" bin/
        cp "$OPENSSL_DIR/lib/libcrypto.3.dylib" bin/
        echo "[INFO] Copied libssl.3.dylib and libcrypto.3.dylib to bin/"

        # Fix OpenSSL dylib install_names with @executable_path
        install_name_tool -id "@executable_path/libssl.3.dylib" bin/libssl.3.dylib
        install_name_tool -id "@executable_path/libcrypto.3.dylib" bin/libcrypto.3.dylib
        install_name_tool -change "$OPENSSL_DIR/lib/libcrypto.3.dylib" "@executable_path/libcrypto.3.dylib" bin/libssl.3.dylib
    else
        # MySQL and PostgreSQL: lib/ subdirectory approach
        echo "[INFO] Bundling OpenSSL shared libraries..."
        mkdir -p lib
        cp "$OPENSSL_DIR/lib/libssl.3.dylib" lib/
        cp "$OPENSSL_DIR/lib/libcrypto.3.dylib" lib/
        echo "[INFO] Copied libssl.3.dylib and libcrypto.3.dylib"

        # Fix OpenSSL dylib install_names in lib/
        install_name_tool -id "@loader_path/libssl.3.dylib" lib/libssl.3.dylib
        install_name_tool -id "@loader_path/libcrypto.3.dylib" lib/libcrypto.3.dylib
        install_name_tool -change "$OPENSSL_DIR/lib/libcrypto.3.dylib" "@loader_path/libcrypto.3.dylib" lib/libssl.3.dylib
    fi
}

fix_dylib_paths() {
    local service="$1"

    echo "[INFO] Fixing library paths for portability..."
    cd "$INSTALL_DIR"

    # Store the hardcoded paths that binaries were compiled with
    OLD_SSL_PATH="$OPENSSL_DIR/lib/libssl.3.dylib"
    OLD_CRYPTO_PATH="$OPENSSL_DIR/lib/libcrypto.3.dylib"

    if [[ "$service" == "redis" || "$service" == "valkey" ]]; then
        # Redis/Valkey: everything in bin/ with @executable_path
        echo "[INFO] Fixing dependencies in bin/* with @executable_path..."
        for file in bin/*; do
            [[ -f "$file" ]] || continue
            # Change absolute OpenSSL paths to @executable_path (same directory)
            install_name_tool -change "$OLD_SSL_PATH" "@executable_path/libssl.3.dylib" "$file" 2>/dev/null || true
            install_name_tool -change "$OLD_CRYPTO_PATH" "@executable_path/libcrypto.3.dylib" "$file" 2>/dev/null || true
        done
    else
        # PostgreSQL also needs libpq fixed
        if [[ "$service" == "postgresql" ]]; then
            OLD_PQ_PATH="$INSTALL_DIR/lib/libpq.5.dylib"

            # Fix libpq install_name
            if [[ -f lib/libpq.5.dylib ]]; then
                install_name_tool -id "@loader_path/libpq.5.dylib" lib/libpq.5.dylib
            fi
        fi

        # Step 1: Fix all dylibs and plugins in lib/ directory (including subdirectories)
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

            # Change absolute OpenSSL paths to relative paths
            install_name_tool -change "$OLD_SSL_PATH" "$PREFIX/libssl.3.dylib" "$file" 2>/dev/null || true
            install_name_tool -change "$OLD_CRYPTO_PATH" "$PREFIX/libcrypto.3.dylib" "$file" 2>/dev/null || true

            # PostgreSQL: fix libpq path
            if [[ "$service" == "postgresql" ]]; then
                install_name_tool -change "$OLD_PQ_PATH" "$PREFIX/libpq.5.dylib" "$file" 2>/dev/null || true
            fi
        done

        # Step 2: Fix all binaries in bin/ directory
        echo "[INFO] Fixing dependencies in bin/*..."
        for file in bin/*; do
            [[ -f "$file" ]] || continue
            # Change absolute paths to relative @loader_path/../lib (errors ignored for scripts)
            install_name_tool -change "$OLD_SSL_PATH" "@loader_path/../lib/libssl.3.dylib" "$file" 2>/dev/null || true
            install_name_tool -change "$OLD_CRYPTO_PATH" "@loader_path/../lib/libcrypto.3.dylib" "$file" 2>/dev/null || true

            # PostgreSQL: fix libpq path
            if [[ "$service" == "postgresql" ]]; then
                install_name_tool -change "$OLD_PQ_PATH" "@loader_path/../lib/libpq.5.dylib" "$file" 2>/dev/null || true
            fi
        done
    fi

    echo "[INFO] Library path fixing completed"
}

create_archive() {
    local service="$1"

    cd "$INSTALL_DIR"

    echo "[INFO] Creating portable tarball..."

    if [[ "$service" == "redis" || "$service" == "valkey" ]]; then
        # Redis/Valkey: Archive only bin/ directory
        tar -cJf "$WORKDIR/$ARCHIVE" -C bin .
    else
        # Other services: Archive entire structure
        tar -cJf "$WORKDIR/$ARCHIVE" .
    fi

    echo "[SUCCESS] Created: $ARCHIVE ($(du -sh "$WORKDIR/$ARCHIVE" | cut -f1))"
    echo "[INFO] Archive location: $WORKDIR/$ARCHIVE"
    echo "[INFO] $service ready for distribution"
}

# ================================
# SERVICE-SPECIFIC BUILD FUNCTIONS
# ================================

build_mysql() {
    local version="$1"

    echo "[INFO] Building MySQL $version..."
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

    export INSTALL_DIR
}

build_postgresql() {
    local version="$1"

    echo "[INFO] Building PostgreSQL $version..."
    cd "$WORKDIR/$SOURCE_DIR"

    # Common flags for both C and C++ (optimized for portable binaries)
    COMMON_FLAGS="-O2 -fno-asynchronous-unwind-tables -arch $(uname -m)"

    echo "[INFO] Configuring PostgreSQL..."
    INSTALL_DIR="$TEMP_DIR/install"
    mkdir -p "$INSTALL_DIR"

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

    export INSTALL_DIR
}

build_mariadb() {
    local version="$1"

    # Extract major version for version-specific configuration
    MAJOR_VERSION=${version%%.*}

    echo "[INFO] Building MariaDB $version..."
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

    export INSTALL_DIR
}

build_redis() {
    local version="$1"

    echo "[INFO] Building Redis $version..."
    cd "$WORKDIR/$SOURCE_DIR"

    # Install build dependencies (Rust for modules)
    if ! command -v rustc >/dev/null 2>&1; then
        echo "[INFO] Installing Rust for Redis modules..."
        brew install rust 2>/dev/null || true
    fi

    # Configure environment for Redis build
    HOMEBREW_PREFIX="$(brew --prefix)"
    export BUILD_WITH_MODULES=yes
    export BUILD_TLS=yes
    export DISABLE_WERRORS=yes
    export OPENSSL_PREFIX="$OPENSSL_DIR"

    # Setup PATH with GNU tools
    export PATH="$HOMEBREW_PREFIX/opt/libtool/libexec/gnubin:$HOMEBREW_PREFIX/opt/llvm@18/bin:$HOMEBREW_PREFIX/opt/make/libexec/gnubin:$HOMEBREW_PREFIX/opt/gnu-sed/libexec/gnubin:$HOMEBREW_PREFIX/opt/coreutils/libexec/gnubin:$PATH"
    export LDFLAGS="-L$HOMEBREW_PREFIX/opt/llvm@18/lib -L$OPENSSL_DIR/lib"
    export CPPFLAGS="-I$HOMEBREW_PREFIX/opt/llvm@18/include -I$OPENSSL_DIR/include"

    echo "[INFO] Compiling Redis (this may take a while)..."
    make all OS=macos

    echo "[INFO] Installing Redis to temporary directory..."
    INSTALL_DIR="$TEMP_DIR/redis-install"
    mkdir -p "$INSTALL_DIR"
    make install PREFIX="$INSTALL_DIR" OS=macos

    export INSTALL_DIR
}

build_valkey() {
    local version="$1"

    echo "[INFO] Building Valkey $version..."
    cd "$WORKDIR/$SOURCE_DIR"

    # Install build dependencies (Rust for modules)
    if ! command -v rustc >/dev/null 2>&1; then
        echo "[INFO] Installing Rust for Valkey modules..."
        brew install rust 2>/dev/null || true
    fi

    # Configure environment for Valkey build
    HOMEBREW_PREFIX="$(brew --prefix)"
    export BUILD_WITH_MODULES=yes
    export BUILD_TLS=yes
    export DISABLE_WERRORS=yes
    export OPENSSL_PREFIX="$OPENSSL_DIR"

    # Setup PATH with GNU tools
    export PATH="$HOMEBREW_PREFIX/opt/libtool/libexec/gnubin:$HOMEBREW_PREFIX/opt/llvm@18/bin:$HOMEBREW_PREFIX/opt/make/libexec/gnubin:$HOMEBREW_PREFIX/opt/gnu-sed/libexec/gnubin:$HOMEBREW_PREFIX/opt/coreutils/libexec/gnubin:$PATH"
    export LDFLAGS="-L$HOMEBREW_PREFIX/opt/llvm@18/lib -L$OPENSSL_DIR/lib"
    export CPPFLAGS="-I$HOMEBREW_PREFIX/opt/llvm@18/include -I$OPENSSL_DIR/include"

    echo "[INFO] Compiling Valkey (this may take a while)..."
    make all OS=macos

    echo "[INFO] Installing Valkey to temporary directory..."
    INSTALL_DIR="$TEMP_DIR/valkey-install"
    mkdir -p "$INSTALL_DIR"
    make install PREFIX="$INSTALL_DIR" OS=macos

    export INSTALL_DIR
}

# ================================
# MAIN
# ================================

SERVICE="$1"
VERSION="$2"

# Validate service
if [[ -z "$SERVICE" ]]; then
    echo "[ERROR] Service parameter required"
    echo "[USAGE] $0 <service> <version>"
    echo "[SERVICES] mysql, postgresql, mariadb, redis, valkey"
    exit 1
fi

case "$SERVICE" in
    mysql|postgresql|mariadb|redis|valkey)
        ;;
    *)
        echo "[ERROR] Unknown service: $SERVICE"
        echo "[SERVICES] mysql, postgresql, mariadb, redis, valkey"
        exit 1
        ;;
esac

# Execute build pipeline
validate_version "$SERVICE" "$VERSION"
setup_workspace "$SERVICE" "$VERSION"
setup_openssl
detect_macos_sdk
git_clone_source "$SERVICE" "$VERSION"

# Service-specific build
case "$SERVICE" in
    mysql)
        build_mysql "$VERSION"
        ;;
    postgresql)
        build_postgresql "$VERSION"
        ;;
    mariadb)
        build_mariadb "$VERSION"
        ;;
    redis)
        build_redis "$VERSION"
        ;;
    valkey)
        build_valkey "$VERSION"
        ;;
esac

# Post-build: bundle, fix paths, archive
bundle_openssl "$SERVICE"
fix_dylib_paths "$SERVICE"
create_archive "$SERVICE"
