#!/bin/sh
set -e

if [ -z "$1" ]; then
    echo "Usage: $0 <formula> [deps_file] [output_file]" >&2
    exit 1
fi

FORMULA="$1"
DEPS_FILE="${2:-/tmp/${FORMULA}_runtime_deps.txt}"
OUTPUT_FILE="${3:-/tmp/${FORMULA}_bottle_paths.txt}"

if [ ! -f "$DEPS_FILE" ]; then
    echo "Error: Dependencies file not found: $DEPS_FILE" >&2
    echo "Run list-runtime-deps.sh first" >&2
    exit 1
fi

rm -f "$OUTPUT_FILE"
touch "$OUTPUT_FILE"

echo "==> Fetching bottles for: $FORMULA" >&2
echo "" >&2

echo "==> Fetching main formula: $FORMULA" >&2
brew fetch --force-bottle "$FORMULA"
BOTTLE_PATH=$(brew --cache --force-bottle "$FORMULA")
echo "$BOTTLE_PATH" >> "$OUTPUT_FILE"
echo "    Cached: $BOTTLE_PATH" >&2
echo "" >&2

DEP_COUNT=$(wc -l < "$DEPS_FILE" | tr -d ' ')
echo "==> Fetching $DEP_COUNT dependencies" >&2
echo "" >&2

CURRENT=0
while IFS= read -r dep; do
    [ -z "$dep" ] && continue
    CURRENT=$((CURRENT + 1))
    echo "[$CURRENT/$DEP_COUNT] Fetching: $dep" >&2

    brew fetch --force-bottle "$dep"
    BOTTLE_PATH=$(brew --cache --force-bottle "$dep")
    echo "$BOTTLE_PATH" >> "$OUTPUT_FILE"
    echo "            Cached: $BOTTLE_PATH" >&2
done < "$DEPS_FILE"

TOTAL=$(wc -l < "$OUTPUT_FILE" | tr -d ' ')

echo "" >&2
echo "==> Summary:" >&2
echo "    Formula: $FORMULA" >&2
echo "    Dependencies: $DEP_COUNT" >&2
echo "    Total bottles fetched: $TOTAL" >&2
echo "    Bottle paths saved to: $OUTPUT_FILE" >&2
echo "" >&2
