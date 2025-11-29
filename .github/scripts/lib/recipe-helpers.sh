#!/bin/bash
# Helper functions for recipe metadata
# Centralizes URL templates to avoid version duplication in recipes

# Get package URL from service type and version
# Usage: get_package_url <service> <version>
get_package_url() {
    local service="$1"
    local version="$2"
    local major_minor="${version%.*}"  # e.g., 12.1.2 -> 12.1

    case "$service" in
        mariadb)
            echo "https://archive.mariadb.org/mariadb-${version}/source/mariadb-${version}.tar.gz"
            ;;
        mysql)
            echo "https://cdn.mysql.com/Downloads/MySQL-${major_minor}/mysql-${version}.tar.gz"
            ;;
        postgresql)
            echo "https://ftp.postgresql.org/pub/source/v${version}/postgresql-${version}.tar.bz2"
            ;;
        redis)
            echo "https://download.redis.io/releases/redis-${version}.tar.gz"
            ;;
        valkey)
            echo "https://github.com/valkey-io/valkey/archive/refs/tags/${version}.tar.gz"
            ;;
        *)
            echo "Unknown service: $service" >&2
            return 1
            ;;
    esac
}

# Derive PACKAGE_NAME from recipe filename
# e.g., mariadb@12.1.sh -> mariadb@12.1
# Usage: get_package_name (call from within a recipe)
get_package_name() {
    basename "${BASH_SOURCE[1]}" .sh
}
