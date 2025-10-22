#!/bin/bash
# Build recipe for ca-certificates (Mozilla CA certificate bundle)
# Source: https://curl.se/docs/caextract.html

set -e

# Metadata
export PACKAGE_NAME="ca-certificates"
export PACKAGE_VERSION="2025-09-09"
export PACKAGE_URL="https://curl.se/ca/cacert-2025-09-09.pem"
export PACKAGE_SHA256="f290e6acaf904a4121424ca3ebdd70652780707e28e8af999221786b86bb1975"

# No dependencies
export DEPENDENCIES=()

# Build function (not needed, just install)
build() {
    local PREFIX="$1"
    local SOURCE_DIR="$2"

    echo "Installing ca-certificates ${PACKAGE_VERSION}..."

    # Create destination directory
    mkdir -p "${PREFIX}/share/ca-certificates"

    # Copy the PEM file
    cp "${SOURCE_DIR}/cacert-${PACKAGE_VERSION}.pem" \
       "${PREFIX}/share/ca-certificates/cacert.pem"

    echo "✓ ca-certificates installed successfully"
}
