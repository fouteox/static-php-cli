#!/usr/bin/env bash
set -euo pipefail

# ================================
# SERVICES VERSION CHECKER
# ================================
# Vérifie les dernières versions disponibles pour MariaDB, MySQL, PostgreSQL, Redis et Valkey
# Utilise l'API endoflife.date

# ================================
# CONFIGURATION
# ================================

# Services à vérifier
SERVICES="mariadb mysql postgresql redis valkey"

# Source la configuration centralisée des services
source "$(dirname "$0")/.github/config/services-config.sh"

# Configuration des versions majeures par service (délègue au config central)
get_service_versions() {
    local service="$1"
    get_supported_versions "$service"
}

# ================================
# FONCTIONS UTILITAIRES
# ================================

function log_info() {
    echo "[INFO] $1" >&2
}

function log_error() {
    echo "[ERROR] $1" >&2
}

function check_command() {
    command -v "$1" >/dev/null 2>&1 || {
        log_error "$1 n'est pas installé."
        exit 1
    }
}

function check_prerequisites() {
    log_info "Vérification des prérequis..."
    check_command curl
    check_command jq
}

# ================================
# ENDOFLIFE.DATE API
# ================================

function get_latest_from_endoflife() {
    local service="$1"
    local major_version="$2"
    local api_url="https://endoflife.date/api/$service.json"

    # Appel API endoflife.date
    local response
    response=$(curl -s "$api_url" 2>/dev/null)

    if [[ -z "$response" ]]; then
        log_error "Erreur lors de l'appel API endoflife.date pour $service"
        return 1
    fi

    # Extraction de la version latest selon le service
    local latest_version
    case "$service" in
        "mariadb")
            # MariaDB utilise des cycles comme "11.8", "10.11", "12.0"
            # On cherche le cycle actif qui correspond à la version majeure
            latest_version=$(echo "$response" | jq -r "
                [.[] | select(.cycle | startswith(\"$major_version.\")) | select(.eol == false or (.eol | type) == \"string\")]
                | sort_by(.releaseDate)
                | reverse
                | .[0].latest
            ")
            ;;
        "mysql"|"redis"|"valkey")
            # MySQL, Redis et Valkey utilisent des cycles comme "9.4", "8.4", "7.4", "8.2", "8.1"
            # On cherche le cycle le plus récent pour la version majeure
            latest_version=$(echo "$response" | jq -r "
                [.[] | select(.cycle | startswith(\"$major_version.\"))]
                | sort_by(.releaseDate)
                | reverse
                | .[0].latest
            ")
            ;;
        *)
            # Pour PostgreSQL : cycles directs "14", "15", "16", "17", "18", etc.
            latest_version=$(echo "$response" | jq -r ".[] | select(.cycle == \"$major_version\") | .latest")
            ;;
    esac

    if [[ "$latest_version" == "null" || -z "$latest_version" ]]; then
        log_error "Version majeure $major_version non trouvée pour $service"
        return 1
    fi

    echo "$latest_version"
}

# ================================
# DÉTECTION DES VERSIONS PAR SERVICE
# ================================

function get_latest_version() {
    local service="$1"
    local major_version="$2"

    # Utilisation exclusive de l'API endoflife.date
    get_latest_from_endoflife "$service" "$major_version"
}

function check_service_versions() {
    local service="$1"
    local major_versions

    major_versions=$(get_service_versions "$service")

    echo "[$service]"

    for major in $major_versions; do
        local version
        version=$(get_latest_version "$service" "$major")

        if [[ -n "$version" ]]; then
            echo "  v$major: $version (latest stable)"
        else
            echo "  v$major: ERROR - version non trouvée"
        fi
    done

    echo ""
}

# ================================
# MAIN
# ================================

function main() {
    echo "=== SERVICES VERSION CHECK ==="
    echo ""

    check_prerequisites

    # Vérifier chaque service
    for service in $SERVICES; do
        log_info "Vérification des versions $service..."
        check_service_versions "$service" 2>/dev/null
    done

    log_info "Vérification terminée"
}

# Exécution du script
main "$@"