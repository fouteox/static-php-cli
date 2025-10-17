#!/bin/sh

# Script to check if a specific service version exists in Homebrew
# Usage: ./check-brew-version.sh <service> <version>
# Example: ./check-brew-version.sh postgresql 15.14.2

# Check parameters
if [ $# -ne 2 ]; then
    exit 2
fi

service="$1"
requested_version="$2"

# Extract version components (major.minor.patch)
version_major=$(echo "$requested_version" | cut -d. -f1)
version_minor=$(echo "$requested_version" | cut -d. -f2)
version_patch=$(echo "$requested_version" | cut -d. -f3)

# Build list of formula candidates to test, ordered by probability
candidates=""

# If we have patch, try service@major.minor.patch
if [ -n "$version_patch" ] && [ "$version_patch" != "$requested_version" ]; then
    candidates="$candidates ${service}@${version_major}.${version_minor}.${version_patch}"
fi

# If we have minor, try service@major.minor
if [ -n "$version_minor" ] && [ "$version_minor" != "$requested_version" ]; then
    candidates="$candidates ${service}@${version_major}.${version_minor}"
fi

# Try service@major
candidates="$candidates ${service}@${version_major}"

# Try service without version (main formula)
candidates="$candidates ${service}"

# Test each candidate
for formula in $candidates; do
    # Extract stable version with brew info and jq
    stable_version=$(brew info "$formula" --json=v2 2>/dev/null | jq -r '.formulae[0].versions.stable // empty')

    # If no version available or formula doesn't exist, continue
    if [ -z "$stable_version" ] || [ "$stable_version" = "null" ]; then
        continue
    fi

    # Compare exactly with requested version
    if [ "$stable_version" = "$requested_version" ]; then
        echo "$formula"
        exit 0
    fi
done

# No exact match found
exit 1
