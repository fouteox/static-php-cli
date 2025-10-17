#!/bin/sh
set -e

if [ -z "$1" ]; then
    echo "Usage: $0 <formula>" >&2
    echo "" >&2
    echo "Example: $0 mariadb" >&2
    echo "         $0 postgresql" >&2
    echo "         $0 redis" >&2
    exit 1
fi

FORMULA="$1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Extract service name (remove @version suffix) and real version
SERVICE_NAME=$(echo "$FORMULA" | sed 's/@.*//')
VERSION=$(brew info --json=v2 "$FORMULA" | jq -r '.formulae[0].versions.stable')

if [ -z "$VERSION" ]; then
    echo "Error: Could not determine version for '$FORMULA'" >&2
    exit 1
fi

BUNDLE_DIR="${SERVICE_NAME}-${VERSION}"
ARCHIVE_NAME="${SERVICE_NAME}-${VERSION}.tar.gz"

echo "==> Creating portable package: $FORMULA ($VERSION)" >&2
echo "" >&2

if ! brew info "$FORMULA" >/dev/null 2>&1; then
    echo "Error: Formula '$FORMULA' not found in Homebrew" >&2
    exit 1
fi

echo "==> Step 1/6: Analyzing runtime dependencies" >&2
if ! "$SCRIPT_DIR/list-runtime-deps.sh" "$FORMULA"; then
    echo "Error: Failed to list dependencies" >&2
    exit 1
fi
echo "" >&2

echo "==> Step 2/6: Fetching bottles" >&2
if ! "$SCRIPT_DIR/fetch-all-bottles.sh" "$FORMULA"; then
    echo "Error: Failed to fetch bottles" >&2
    exit 1
fi
echo "" >&2

echo "==> Step 3/6: Extracting runtime files" >&2
if ! "$SCRIPT_DIR/extract-dylibs.sh" "$FORMULA" "/tmp/${FORMULA}_bottle_paths.txt" "$BUNDLE_DIR"; then
    echo "Error: Failed to extract files" >&2
    exit 1
fi
echo "" >&2

echo "==> Step 4/6: Relocating binaries" >&2
if ! "$SCRIPT_DIR/relocate-binaries.sh" "$FORMULA" "$BUNDLE_DIR"; then
    echo "Error: Failed to relocate binaries" >&2
    exit 1
fi
echo "" >&2

echo "==> Step 5/6: Code signing" >&2
if [ -x "$SCRIPT_DIR/sign-binaries.sh" ]; then
    chmod -R u+w "$BUNDLE_DIR" 2>/dev/null || true
    xattr -cr "$BUNDLE_DIR" 2>/dev/null || true
    if ! "$SCRIPT_DIR/sign-binaries.sh" "$FORMULA" "$BUNDLE_DIR"; then
        echo "Error: Failed to sign binaries" >&2
        exit 1
    fi
else
    echo "    Warning: sign-binaries.sh not found, skipping code signing" >&2
fi
echo "" >&2

echo "==> Step 6/6: Creating archive" >&2
if [ -d "$BUNDLE_DIR" ]; then
    tar -czf "$ARCHIVE_NAME" "$BUNDLE_DIR"
    echo "    Created: $ARCHIVE_NAME" >&2
else
    echo "Error: Bundle directory not found: $BUNDLE_DIR" >&2
    exit 1
fi
echo "" >&2

ARCHIVE_SIZE=$(du -sh "$ARCHIVE_NAME" | awk '{print $1}')
BIN_COUNT=$(find "$BUNDLE_DIR/bin" -type f 2>/dev/null | wc -l | tr -d ' ')
LIB_COUNT=$(find "$BUNDLE_DIR/lib" -name "*.dylib" -type f 2>/dev/null | wc -l | tr -d ' ')

echo "==> Package created successfully" >&2
echo "    Formula: $FORMULA" >&2
echo "    Archive: $ARCHIVE_NAME ($ARCHIVE_SIZE)" >&2
echo "    Binaries: $BIN_COUNT | Libraries: $LIB_COUNT" >&2
echo "" >&2
