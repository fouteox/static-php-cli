#!/bin/bash
# Build recipe for mariadb@10.11 10.11.14
# Translated from: homebrew-core/Formula/m/mariadb@10.11.rb
# Description: Drop-in replacement for MySQL

set -e

# Metadata
export PACKAGE_NAME="mariadb@10.11"
export PACKAGE_VERSION="10.11.14"
export PACKAGE_URL="https://archive.mariadb.org/mariadb-10.11.14/source/mariadb-10.11.14.tar.gz"
export PACKAGE_SHA256="8a571cb14fb1d4e3663d8e98f3d4200c042fc8b2a4aaaab495860dea8b7d052f"

# Runtime dependencies
export DEPENDENCIES=(
    "groonga"
    "lz4"
    "lzo"
    "openssl@3"
    "pcre2"
    "xz"
    "zlib"
    "zstd"
)

# Build dependencies (via Homebrew, not in bundle)
export BUILD_DEPENDENCIES=(
    "bison"
    "cmake"
    "fmt"
    "openjdk"
    "pkgconf"
)

# Build function
build() {
    local PREFIX="$1"
    local SOURCE_DIR="$2"

    echo "Building ${PACKAGE_NAME} ${PACKAGE_VERSION}..."

    # Set PKG_CONFIG_PATH to find our zlib (and other deps)
    export PKG_CONFIG_PATH="${PREFIX}/lib/pkgconfig"
    # Add headerpad for install_name_tool (CRITICAL for relocation)
    # Force linker to search bundle libs FIRST before system libs
    export LDFLAGS="-L${PREFIX}/lib -Wl,-headerpad_max_install_names"
    # Don't set CPPFLAGS - it pollutes header search order for C++

    # Find Homebrew bison (MariaDB requires newer bison than system provides)
    local BISON_PATH="/opt/homebrew/opt/bison/bin/bison"
    if [ ! -f "$BISON_PATH" ]; then
        BISON_PATH="/usr/local/opt/bison/bin/bison"  # Intel Mac
    fi

    cd "${SOURCE_DIR}"

    # Fix mysql_install_db.sh to use our prefix
    echo "→ Patching mysql_install_db.sh..."
    sed -i.bak "s|^basedir=.*|basedir=\"${PREFIX}\"|" scripts/mysql_install_db.sh
    sed -i.bak "s|^ldata=.*|ldata=\"${PREFIX}/data\"|" scripts/mysql_install_db.sh

    # Remove bundled libraries (as per Homebrew formula)
    echo "→ Removing bundled libraries..."
    rm -rf storage/mroonga/vendor/groonga
    rm -rf extra/wolfssl
    rm -rf zlib
    echo "✓ Bundled libraries cleaned"

    # Find Homebrew fmt location
    local FMT_DIR="/opt/homebrew/opt/fmt"

    # Configure with CMake
    # -DINSTALL_* are relative to CMAKE_INSTALL_PREFIX
    cmake -S . -B build \
        -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
        -DCMAKE_PREFIX_PATH="${PREFIX}" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_FIND_FRAMEWORK=LAST \
        -DCMAKE_VERBOSE_MAKEFILE=ON \
        -DCOMPILATION_COMMENT=Fadogen \
        -DMYSQL_DATADIR="${PREFIX}/data" \
        -DINSTALL_INCLUDEDIR=include/mysql \
        -DINSTALL_MANDIR=share/man \
        -DINSTALL_DOCDIR=share/doc/mariadb \
        -DINSTALL_INFODIR=share/info \
        -DINSTALL_MYSQLSHAREDIR=share/mysql \
        -DINSTALL_SYSCONFDIR="${PREFIX}/etc" \
        -DBISON_EXECUTABLE="${BISON_PATH}" \
        -DLIBFMT_INCLUDE_DIR="${FMT_DIR}/include" \
        -DPCRE2_INCLUDE_DIR="${PREFIX}/include" \
        -DPCRE2_LIBRARY="${PREFIX}/lib/libpcre2-8.dylib" \
        -DOPENSSL_ROOT_DIR="${PREFIX}" \
        -DZLIB_INCLUDE_DIR="${PREFIX}/include" \
        -DZLIB_LIBRARY="${PREFIX}/lib/libz.dylib" \
        -DPLUGIN_PROVIDER_SNAPPY=NO \
        -DWITH_ROCKSDB_Snappy=OFF \
        -DWITH_LIBFMT=system \
        -DWITH_PCRE=system \
        -DWITH_SSL=system \
        -DWITH_ZLIB=system \
        -DWITH_UNIT_TESTS=OFF \
        -DDEFAULT_CHARSET=utf8mb4 \
        -DDEFAULT_COLLATION=utf8mb4_general_ci

    # Build
    cmake --build build -j"$(sysctl -n hw.ncpu)"

    # Install directly to final location
    cmake --install build

    # Save space: remove test and benchmark directories (as per Homebrew formula)
    rm -rf "${PREFIX}/mariadb-test"
    rm -rf "${PREFIX}/sql-bench"

    # Install scripts symlinks (as per Homebrew formula)
    ln -sf "${PREFIX}/scripts/mariadb-install-db" "${PREFIX}/bin/mariadb-install-db"
    ln -sf "${PREFIX}/scripts/mysql_install_db" "${PREFIX}/bin/mysql_install_db"

    # Fix mysql.server script PATH
    if [ -f "${PREFIX}/support-files/mysql.server" ]; then
        sed -i.bak 's|^PATH="\(.*\)"|PATH="\1:'"${PREFIX}"'/bin"|' "${PREFIX}/support-files/mysql.server"
        rm -f "${PREFIX}/support-files/mysql.server.bak"

        # Fix user variable (as per Homebrew formula)
        sed -i.bak "s|^user='mysql'|user=\$(whoami)|" "${PREFIX}/support-files/mysql.server"
        rm -f "${PREFIX}/support-files/mysql.server.bak"

        # Install symlink
        ln -sf "${PREFIX}/support-files/mysql.server" "${PREFIX}/bin/mysql.server"
    fi

    # Move wsrep_sst_common to libexec (as per Homebrew formula)
    if [ -f "${PREFIX}/bin/wsrep_sst_common" ]; then
        mkdir -p "${PREFIX}/libexec"
        mv "${PREFIX}/bin/wsrep_sst_common" "${PREFIX}/libexec/"

        # Fix references in wsrep scripts
        for script in wsrep_sst_mysqldump wsrep_sst_rsync wsrep_sst_mariabackup; do
            if [ -f "${PREFIX}/bin/${script}" ]; then
                sed -i.bak "s|^\\\(.*\\\)\$(dirname \"$0\")/wsrep_sst_common|\\\1${PREFIX}/libexec/wsrep_sst_common|" "${PREFIX}/bin/${script}"
                rm -f "${PREFIX}/bin/${script}.bak"
            fi
        done
    fi

    # Install my.cnf that binds to 127.0.0.1 by default (as per Homebrew formula)
    mkdir -p "${PREFIX}/etc"
    cat > "${PREFIX}/etc/my.cnf" <<'EOF'
# Default Homebrew MySQL server config
[mysqld]
# Only allow connections from localhost
bind-address = 127.0.0.1
EOF

    # Fix my.cnf to point to our PREFIX etc instead of /etc (as per Homebrew formula)
    mkdir -p "${PREFIX}/etc/my.cnf.d"
    if [ -f "${PREFIX}/etc/my.cnf" ]; then
        sed -i.bak "s|!includedir /etc/my.cnf.d|!includedir ${PREFIX}/etc/my.cnf.d|" "${PREFIX}/etc/my.cnf"
        rm -f "${PREFIX}/etc/my.cnf.bak"
    fi
    touch "${PREFIX}/etc/my.cnf.d/.homebrew_dont_prune_me"

    echo "✓ ${PACKAGE_NAME} built successfully"
}
