#!/bin/sh
set -e

if [ -z "$1" ]; then
    echo "Usage: $0 <formula> [output_file]" >&2
    exit 1
fi

FORMULA="$1"
OUTPUT_FILE="${2:-/tmp/${FORMULA}_runtime_deps.txt}"

PROCESSED="/tmp/brew_processed_deps_$$"
ALL_DEPS="/tmp/brew_all_deps_$$"

cleanup() {
    rm -f "$PROCESSED" "$ALL_DEPS"
}
trap cleanup EXIT

rm -f "$PROCESSED" "$ALL_DEPS"
touch "$PROCESSED" "$ALL_DEPS"

get_deps_recursive() {
    formula="$1"

    if grep -q "^${formula}$" "$PROCESSED" 2>/dev/null; then
        return
    fi

    echo "$formula" >> "$PROCESSED"

    if ! brew info --json=v2 "$formula" >/dev/null 2>&1; then
        return
    fi

    deps=$(brew info --json=v2 "$formula" 2>/dev/null | \
           jq -r '.formulae[0].dependencies[]? // empty' 2>/dev/null)

    OLDIFS="$IFS"
    IFS='
'
    for dep in $deps; do
        [ -z "$dep" ] && continue
        echo "$dep" >> "$ALL_DEPS"
        get_deps_recursive "$dep"
    done
    IFS="$OLDIFS"
}

echo "==> Analyzing dependencies: $FORMULA" >&2

if ! brew info "$FORMULA" >/dev/null 2>&1; then
    echo "Error: Formula '$FORMULA' not found" >&2
    exit 1
fi

get_deps_recursive "$FORMULA"

sort -u "$ALL_DEPS" > "$OUTPUT_FILE"

TOTAL=$(wc -l < "$OUTPUT_FILE" | tr -d ' ')

echo "    Found $TOTAL runtime dependencies" >&2
