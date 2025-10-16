#!/usr/bin/env bash
set -euo pipefail

# ================================
# SERVICES METADATA MANAGER
# ================================
# Manages metadata-services.json for all database services
# Commands:
#   check-versions    - Compare metadata with endoflife.date API and generate build matrix
#   update-metadata   - Update metadata-services.json with build results

# ================================
# CONFIGURATION
# ================================

# Source centralized services config
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
CONFIG_PATH="${SCRIPT_DIR}/../config/services-config.sh"
# shellcheck source=../config/services-config.sh
source "$CONFIG_PATH"

METADATA_FILE="${METADATA_FILE:-metadata-services.json}"

# ================================
# UTILITY FUNCTIONS
# ================================

log_info() {
    echo "[INFO] $1" >&2
}

log_error() {
    echo "[ERROR] $1" >&2
    exit 1
}

check_prerequisites() {
    for cmd in curl jq; do
        command -v "$cmd" >/dev/null 2>&1 || log_error "$cmd is required but not installed"
    done
}

# ================================
# ENDOFLIFE.DATE API FUNCTIONS
# ================================

get_latest_from_api() {
    local service="$1"
    local major_version="$2"
    local api_url="https://endoflife.date/api/${service}.json"

    local response
    response=$(curl -s "$api_url" 2>/dev/null)

    if [[ -z "$response" ]]; then
        log_error "Failed to fetch API for $service"
    fi

    local latest_version
    case "$service" in
        postgresql)
            # PostgreSQL uses exact cycle match (e.g., "16", "17")
            latest_version=$(echo "$response" | jq -r ".[] | select(.cycle == \"$major_version\") | .latest")
            ;;
        mariadb|mysql|redis|valkey)
            # These use cycle prefix match (e.g., "11.8" for major "11")
            latest_version=$(echo "$response" | jq -r "
                [.[] | select(.cycle | startswith(\"$major_version.\"))]
                | sort_by(.releaseDate)
                | reverse
                | .[0].latest
            ")
            ;;
    esac

    if [[ "$latest_version" == "null" || -z "$latest_version" ]]; then
        log_error "Version $major_version not found for $service"
    fi

    echo "$latest_version"
}

# ================================
# CHECK VERSIONS COMMAND
# ================================

check_versions() {
    log_info "Checking service versions..."

    # Initialize or load existing metadata
    local metadata='{}'
    if [[ -f "$METADATA_FILE" ]]; then
        metadata=$(cat "$METADATA_FILE")
        log_info "Loaded existing metadata"
    else
        log_info "Creating new metadata"
    fi

    # Build matrix array
    local matrix_items=()

    # Iterate over all services
    for service in $AVAILABLE_SERVICES; do
        log_info "Checking $service..."

        # Get supported major versions for this service
        local major_versions
        major_versions=$(get_supported_versions "$service")

        # Check each major version
        for major in $major_versions; do
            # Get latest version from API
            local api_latest
            api_latest=$(get_latest_from_api "$service" "$major")

            # Get current version from metadata (if exists)
            local metadata_latest
            metadata_latest=$(echo "$metadata" | jq -r ".\"$service\".\"$major\".latest // \"\"")

            # Compare versions
            if [[ "$api_latest" != "$metadata_latest" ]]; then
                if [[ -z "$metadata_latest" ]]; then
                    log_info "  New: ${service} ${major} -> ${api_latest}"
                else
                    log_info "  Update: ${service} ${major} -> ${api_latest} (was: ${metadata_latest})"
                fi

                # Add to build matrix
                matrix_items+=("{\"service\": \"$service\", \"version\": \"$api_latest\", \"major\": \"$major\"}")
            else
                log_info "  OK: ${service} ${major} = ${api_latest}"
            fi
        done
    done

    # Build matrix JSON
    local matrix_json
    if [[ ${#matrix_items[@]} -eq 0 ]]; then
        matrix_json='{"include":[]}'
        echo "should-build=false" >> "${GITHUB_OUTPUT:-/dev/stdout}"
        log_info "No builds needed"
    else
        # Sort matrix: MySQL first (slowest build), then others alphabetically
        local matrix_items_str
        matrix_items_str=$(printf '%s\n' "${matrix_items[@]}" | \
            jq -s 'sort_by(.service) | sort_by(if .service == "mysql" then 0 else 1 end)' | \
            jq -c '.[]' | tr '\n' ',' | sed 's/,$//')
        matrix_json=$(echo "{\"include\": [$matrix_items_str]}" | jq -c)
        echo "should-build=true" >> "${GITHUB_OUTPUT:-/dev/stdout}"
        log_info "Build matrix generated with ${#matrix_items[@]} items (MySQL prioritized)"
    fi

    echo "build-matrix=$matrix_json" >> "${GITHUB_OUTPUT:-/dev/stdout}"
    log_info "Check versions completed"
}

# ================================
# UPDATE METADATA COMMAND
# ================================

update_metadata() {
    log_info "Updating metadata..."

    # Load existing metadata or create new
    local metadata='{}'
    if [[ -f "$METADATA_FILE" ]]; then
        metadata=$(cat "$METADATA_FILE")
        log_info "Loaded existing metadata"
    else
        log_info "Creating new metadata"
    fi

    # Read checksums from stdin (format: service,version,major,sha256,filename)
    local checksums_input
    checksums_input=$(cat)

    if [[ -z "$checksums_input" ]]; then
        log_error "No checksums provided via stdin"
    fi

    # Process each checksum line
    while IFS=',' read -r service version major sha256 filename; do
        [[ -z "$service" ]] && continue

        log_info "  Updating $service $major ($version)"

        # Update metadata using jq
        metadata=$(echo "$metadata" | jq -c \
            --arg service "$service" \
            --arg major "$major" \
            --arg latest "$version" \
            --arg sha256 "$sha256" \
            --arg filename "$filename" \
            '.[$service][$major] = {
                "latest": $latest,
                "sha256": $sha256,
                "filename": $filename
            }')
    done <<< "$checksums_input"

    # Save updated metadata
    echo "$metadata" | jq '.' > "$METADATA_FILE"
    log_info "Metadata updated successfully: $METADATA_FILE"
}

# ================================
# MAIN
# ================================

main() {
    check_prerequisites

    local command="${1:-}"
    case "$command" in
        check-versions)
            check_versions
            ;;
        update-metadata)
            update_metadata
            ;;
        *)
            log_error "Usage: $0 {check-versions|update-metadata}"
            ;;
    esac
}

main "$@"
