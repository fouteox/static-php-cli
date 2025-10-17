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
    indent="$2"

    if grep -q "^${formula}$" "$PROCESSED" 2>/dev/null; then
        return
    fi

    echo "$formula" >> "$PROCESSED"
    echo "${indent}→ $formula" >&2

    if ! brew info --json=v2 "$formula" >/dev/null 2>&1; then
        echo "${indent}  ⚠ Warning: Formula '$formula' not found" >&2
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
        get_deps_recursive "$dep" "  ${indent}"
    done
    IFS="$OLDIFS"
}

echo "==> Analyzing runtime dependencies for: $FORMULA" >&2
echo "" >&2

if ! brew info "$FORMULA" >/dev/null 2>&1; then
    echo "Error: Formula '$FORMULA' not found" >&2
    exit 1
fi

get_deps_recursive "$FORMULA" ""

echo "" >&2
echo "==> Complete runtime dependency list:" >&2
echo "" >&2

sort -u "$ALL_DEPS" | tee "$OUTPUT_FILE"

TOTAL=$(sort -u "$ALL_DEPS" | wc -l | tr -d ' ')

echo "" >&2
echo "==> Summary:" >&2
echo "    Formula: $FORMULA" >&2
echo "    Runtime dependencies: $TOTAL" >&2
echo "    Output file: $OUTPUT_FILE" >&2
echo "" >&2
