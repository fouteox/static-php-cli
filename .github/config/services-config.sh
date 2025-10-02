#!/usr/bin/env bash
# ================================
# CONFIGURATION CENTRALISÉE DES SERVICES
# ================================
# Source unique de vérité pour toutes les versions supportées
# Utilisé par tous les scripts : check-services-versions.sh, services_build_manager.py, scripts de build

# Liste des services disponibles
AVAILABLE_SERVICES="mariadb mysql postgresql redis valkey"

# Fonction utilitaire : obtenir les versions supportées pour un service
get_supported_versions() {
    local service="$1"
    if [[ -z "$service" ]]; then
        echo "Usage: get_supported_versions <service>" >&2
        return 1
    fi

    case "$service" in
        "mariadb")
            echo "10 11 12"
            ;;
        "mysql")
            echo "8 9"
            ;;
        "postgresql")
            echo "14 15 16 17 18"
            ;;
        "redis")
            echo "7 8"
            ;;
        "valkey")
            echo "7 8"
            ;;
        *)
            echo ""
            ;;
    esac
}

# Fonction utilitaire : vérifier si une version est supportée
is_version_supported() {
    local service="$1"
    local version="$2"

    if [[ -z "$service" || -z "$version" ]]; then
        echo "Usage: is_version_supported <service> <version>" >&2
        return 1
    fi

    local supported_versions
    supported_versions=$(get_supported_versions "$service")

    if [[ " $supported_versions " =~ \ $version\  ]]; then
        return 0  # Version supportée
    else
        return 1  # Version non supportée
    fi
}

# Fonction utilitaire : afficher toutes les configurations
show_all_configs() {
    echo "=== CONFIGURATION DES SERVICES ==="
    for service in $AVAILABLE_SERVICES; do
        local versions
        versions=$(get_supported_versions "$service")
        echo "$service: $versions"
    done
}

# Si le script est exécuté directement (pour debug)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    show_all_configs
fi