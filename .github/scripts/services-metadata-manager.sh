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
    command -v jq >/dev/null 2>&1 || log_error "jq is required but not installed"
}

# ================================
# RECIPE VERSION EXTRACTION
# ================================

get_version_from_recipe() {
    local recipe_name="$1"

    if [[ -z "$recipe_name" ]]; then
        log_error "Recipe name required"
    fi

    local recipe_file="${SCRIPT_DIR}/recipes/${recipe_name}.sh"

    if [[ ! -f "$recipe_file" ]]; then
        log_error "Recipe not found: $recipe_file"
    fi

    # Extract PACKAGE_VERSION from recipe file
    local version
    # shellcheck disable=SC1090
    version=$(source "$recipe_file" && echo "$PACKAGE_VERSION")

    if [[ -z "$version" ]]; then
        log_error "Could not extract PACKAGE_VERSION from $recipe_file"
    fi

    echo "$version"
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

    # Filter services if FILTER_SERVICE is set
    local services_to_check="$AVAILABLE_SERVICES"
    if [[ -n "${FILTER_SERVICE:-}" ]]; then
        services_to_check="$FILTER_SERVICE"
        log_info "Filtering for service: $FILTER_SERVICE"
    fi

    # Iterate over all services
    for service in $services_to_check; do
        # Get supported major versions for this service
        local major_versions
        major_versions=$(get_supported_versions "$service")

        # Check each major version
        for major in $major_versions; do
            # Check if a recipe exists for this service+major
            local recipe_name
            recipe_name=$(get_recipe_for_service_major "$service" "$major")

            if [[ $? -ne 0 || -z "$recipe_name" ]]; then
                log_info "Skip: $service $major (no recipe available)"
                continue
            fi

            # Get version from recipe
            local recipe_version
            recipe_version=$(get_version_from_recipe "$recipe_name")

            if [[ $? -ne 0 || -z "$recipe_version" ]]; then
                log_info "Skip: $service $major (could not extract version from recipe)"
                continue
            fi

            # Get current version from metadata (if exists)
            local metadata_latest
            metadata_latest=$(echo "$metadata" | jq -r ".\"$service\".\"$major\".latest // \"\"")

            # Compare versions
            if [[ "$recipe_version" != "$metadata_latest" ]]; then
                if [[ -z "$metadata_latest" ]]; then
                    log_info "New: ${service} ${major} -> ${recipe_version} (recipe: ${recipe_name})"
                else
                    log_info "Update: ${service} ${major} -> ${recipe_version} (was: ${metadata_latest}, recipe: ${recipe_name})"
                fi

                # Add to build matrix with recipe name
                matrix_items+=("{\"service\": \"$service\", \"version\": \"$recipe_version\", \"major\": \"$major\", \"recipe\": \"$recipe_name\"}")
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
}

# ================================
# UPDATE METADATA COMMAND
# ================================

update_metadata() {
    # Load existing metadata or create new
    local metadata='{}'
    if [[ -f "$METADATA_FILE" ]]; then
        metadata=$(cat "$METADATA_FILE")
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
    log_info "Metadata updated: $METADATA_FILE"
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
