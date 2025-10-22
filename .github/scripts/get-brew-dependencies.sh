#!/opt/homebrew/bin/bash
# Get recursive runtime and build dependencies from Homebrew API
# Usage: ./get-brew-dependencies.sh <package-name>

set -e

# Colors
source "$(dirname "$0")/lib/colors.sh"

# Track visited packages to avoid infinite loops
declare -A VISITED
declare -a DEP_ORDER  # Topological order (dependencies first)

# Try to resolve package name with version fallbacks
resolve_package_name() {
    local package="$1"
    local api_url="https://formulae.brew.sh/api/formula/${package}.json"
    local response
    local base
    local major
    local minor
    local fallback1
    local actual_version

    # Try original name first
    response=$(curl -s "$api_url")

    # Check if package exists (by checking for .name field in JSON)
    if echo "$response" | jq -e '.name' >/dev/null 2>&1; then
        echo "$package"
        return 0
    fi

    # If package not found and contains @x.y version, try @x then base
    if [[ "$package" =~ ^(.+)@([0-9]+)\.([0-9]+)$ ]]; then
        base="${BASH_REMATCH[1]}"
        major="${BASH_REMATCH[2]}"
        minor="${BASH_REMATCH[3]}"
        fallback1="${base}@${major}"

        # Try @x first
        echo -e "${YELLOW}Package '$package' not found, trying '$fallback1'...${NC}" >&2
        response=$(curl -s "https://formulae.brew.sh/api/formula/${fallback1}.json")
        if echo "$response" | jq -e '.name' >/dev/null 2>&1; then
            # Check if version matches major.minor.patch pattern (must have patch version)
            actual_version=$(echo "$response" | jq -r '.versions.stable' 2>/dev/null)
            if [[ "$actual_version" =~ ^${major}\.${minor}\.[0-9]+ ]]; then
                echo -e "${GREEN}✓ Using '$fallback1' (version $actual_version) as alias for '$package'${NC}" >&2
                echo "$fallback1"
                return 0
            else
                echo -e "${RED}✗ '$fallback1' has version $actual_version, doesn't match requested $major.$minor.x${NC}" >&2
            fi
        fi

        # Try without version
        echo -e "${YELLOW}Package '$fallback1' not found, trying '$base'...${NC}" >&2
        response=$(curl -s "https://formulae.brew.sh/api/formula/${base}.json")
        if echo "$response" | jq -e '.name' >/dev/null 2>&1; then
            actual_version=$(echo "$response" | jq -r '.versions.stable' 2>/dev/null)
            # Check if version matches major.minor.patch pattern (must have patch version)
            if [[ "$actual_version" =~ ^${major}\.${minor}\.[0-9]+ ]]; then
                echo -e "${GREEN}✓ Using '$base' (version $actual_version) as alias for '$package'${NC}" >&2
                echo "$base"
                return 0
            else
                echo -e "${RED}✗ '$base' has version $actual_version, doesn't match requested $major.$minor.x${NC}" >&2
            fi
        fi
    fi

    # If package not found and contains @x version, try without version
    if [[ "$package" =~ ^(.+)@([0-9]+)$ ]]; then
        base="${BASH_REMATCH[1]}"
        major="${BASH_REMATCH[2]}"

        echo -e "${YELLOW}Package '$package' not found, trying '$base'...${NC}" >&2
        response=$(curl -s "https://formulae.brew.sh/api/formula/${base}.json")
        if echo "$response" | jq -e '.name' >/dev/null 2>&1; then
            actual_version=$(echo "$response" | jq -r '.versions.stable' 2>/dev/null)
            # Check if version matches major pattern
            if [[ "$actual_version" =~ ^${major}\. ]]; then
                echo -e "${GREEN}✓ Using '$base' (version $actual_version) as alias for '$package'${NC}" >&2
                echo "$base"
                return 0
            else
                echo -e "${RED}✗ '$base' has version $actual_version, doesn't match requested $major${NC}" >&2
            fi
        fi
    fi

    # Package not found
    echo "$package"
    return 1
}

# Fetch package info from Homebrew API
fetch_package_info() {
    local package="$1"
    local api_url="https://formulae.brew.sh/api/formula/${package}.json"

    curl -s "$api_url"
}

# Recursively get dependencies
get_dependencies_recursive() {
    local package="$1"
    local indent="$2"

    # Resolve package name (handle version aliases)
    local resolved_package
    if ! resolved_package=$(resolve_package_name "$package"); then
        echo -e "${indent}${RED}✗ Cannot find package matching '$package'${NC}" >&2
        return 1
    fi

    # Use resolved package name
    package="$resolved_package"

    # Skip if already visited
    if [ -n "${VISITED[$package]}" ]; then
        echo -e "${indent}${YELLOW}↺ $package (already processed)${NC}" >&2
        return 0
    fi

    echo -e "${indent}${BLUE}→ Fetching $package...${NC}" >&2

    # Mark as visited
    VISITED[$package]=1

    # Fetch package info
    local package_json
    package_json=$(fetch_package_info "$package")

    # Check if package exists
    if echo "$package_json" | grep -q "error.*Not Found"; then
        echo -e "${indent}${RED}✗ Package not found: $package${NC}" >&2
        return 1
    fi

    # Extract runtime dependencies
    local deps
    deps=$(echo "$package_json" | jq -r '.dependencies // [] | join(" ")' 2>/dev/null || echo "")

    # Extract build dependencies
    local build_deps
    build_deps=$(echo "$package_json" | jq -r '.build_dependencies // [] | join(" ")' 2>/dev/null || echo "")

    # Process runtime dependencies first (depth-first)
    if [ -n "$deps" ]; then
        echo -e "${indent}${GREEN}Runtime deps: $deps${NC}" >&2
        for dep in $deps; do
            get_dependencies_recursive "$dep" "${indent}  "
        done
    fi

    # Process build dependencies
    if [ -n "$build_deps" ]; then
        echo -e "${indent}${CYAN}Build deps: $build_deps${NC}" >&2
        for dep in $build_deps; do
            get_dependencies_recursive "$dep" "${indent}  "
        done
    fi

    # Add current package to order AFTER its dependencies
    DEP_ORDER+=("$package")
}

# Main
if [ $# -eq 0 ]; then
    echo "Usage: $0 <package-name>"
    echo "Example: $0 postgresql@18"
    echo ""
    echo "This script fetches the recursive runtime and build dependencies of a Homebrew package"
    echo "and outputs them in topological order (dependencies before dependents)."
    exit 1
fi

PACKAGE="$1"

echo -e "${GREEN}=== Fetching dependencies for $PACKAGE ===${NC}" >&2
echo "" >&2

# Get all dependencies recursively
get_dependencies_recursive "$PACKAGE" ""

echo "" >&2
echo -e "${GREEN}=== Dependency order (build from top to bottom) ===${NC}" >&2

# Output in topological order (dependencies first)
for pkg in "${DEP_ORDER[@]}"; do
    echo "$pkg"
done
