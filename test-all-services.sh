#!/bin/sh
set -e

TEST_DIR="/tmp/portable-test-$$"
mkdir -p "$TEST_DIR"

cleanup() {
    rm -rf "$TEST_DIR"
}
trap cleanup EXIT

echo "======================================================================"
echo "Testing Portability of All Packages"
echo "======================================================================"
echo "Test directory: $TEST_DIR"
echo ""

PASS_COUNT=0
FAIL_COUNT=0

# Find all tar.gz archives
for archive in *.tar.gz; do
    [ -f "$archive" ] || continue

    # Extract service name and version from archive name
    BUNDLE_NAME=$(basename "$archive" .tar.gz)
    SERVICE_NAME=$(echo "$BUNDLE_NAME" | sed 's/-[0-9].*//')

    echo "======================================================================"
    echo "Testing: $BUNDLE_NAME"
    echo "======================================================================"

    # Extract to temporary location (test transportability)
    echo "→ Extracting to $TEST_DIR..."
    tar -xzf "$archive" -C "$TEST_DIR"
    BUNDLE_DIR="$TEST_DIR/$BUNDLE_NAME"

    if [ ! -d "$BUNDLE_DIR" ]; then
        echo "❌ FAILED: Extraction failed"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
    fi

    # Determine main binary
    MAIN_BINARY=""
    TEST_CMD=""
    case "$SERVICE_NAME" in
        mariadb)
            MAIN_BINARY="$BUNDLE_DIR/bin/mariadbd"
            TEST_CMD="$MAIN_BINARY --version"
            ;;
        mysql)
            MAIN_BINARY="$BUNDLE_DIR/bin/mysqld"
            TEST_CMD="$MAIN_BINARY --version"
            ;;
        postgresql)
            MAIN_BINARY="$BUNDLE_DIR/bin/postgres"
            TEST_CMD="$MAIN_BINARY --version"
            ;;
        valkey)
            MAIN_BINARY="$BUNDLE_DIR/bin/valkey-server"
            TEST_CMD="$MAIN_BINARY --version"
            ;;
        redis)
            MAIN_BINARY="$BUNDLE_DIR/bin/redis-server"
            TEST_CMD="$MAIN_BINARY --version"
            ;;
        php)
            MAIN_BINARY="$BUNDLE_DIR/bin/php"
            TEST_CMD="$MAIN_BINARY -n -v"
            ;;
        *)
            echo "⚠️  UNKNOWN: Don't know how to test $SERVICE_NAME"
            echo ""
            rm -rf "$BUNDLE_DIR"
            continue
            ;;
    esac

    # Check binary exists
    if [ ! -f "$MAIN_BINARY" ]; then
        echo "❌ FAILED: Main binary not found: $MAIN_BINARY"
        echo ""
        FAIL_COUNT=$((FAIL_COUNT + 1))
        rm -rf "$BUNDLE_DIR"
        continue
    fi

    TESTS_PASSED=0
    TESTS_FAILED=0

    # Test 1: Check for absolute /opt/homebrew paths
    echo ""
    echo "Test 1: Checking for absolute /opt/homebrew paths..."
    find "$BUNDLE_DIR/bin" "$BUNDLE_DIR/lib" -type f 2>/dev/null | while read -r file; do
        if file "$file" 2>/dev/null | grep -q "Mach-O"; then
            if otool -L "$file" 2>/dev/null | grep -q "^\s*/opt/homebrew"; then
                echo "  Found in: $file"
                otool -L "$file" 2>/dev/null | grep "^\s*/opt/homebrew" | head -3
            fi
        fi
    done | head -20

    ABS_PATHS="$(find "$BUNDLE_DIR/bin" "$BUNDLE_DIR/lib" -type f 2>/dev/null | while read -r file; do
        file "$file" 2>/dev/null | grep -q "Mach-O" && otool -L "$file" 2>/dev/null | grep -q "^\s*/opt/homebrew" && echo "1"
    done | wc -l)"

    if [ "$ABS_PATHS" -eq 0 ]; then
        echo "✅ PASS: No absolute /opt/homebrew paths"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "❌ FAIL: Found absolute paths to /opt/homebrew"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi

    # Test 2: Check for @@HOMEBREW placeholders
    echo ""
    echo "Test 2: Checking for @@HOMEBREW placeholders..."
    find "$BUNDLE_DIR/bin" "$BUNDLE_DIR/lib" -type f 2>/dev/null | while read -r file; do
        if file "$file" 2>/dev/null | grep -q "Mach-O"; then
            if otool -L "$file" 2>/dev/null | grep -q "@@HOMEBREW"; then
                echo "  Found in: $(basename "$file")"
            fi
        fi
    done | head -10

    PLACEHOLDERS="$(find "$BUNDLE_DIR/bin" "$BUNDLE_DIR/lib" -type f 2>/dev/null | while read -r file; do
        file "$file" 2>/dev/null | grep -q "Mach-O" && otool -L "$file" 2>/dev/null | grep -q "@@HOMEBREW" && echo "1"
    done | wc -l)"

    if [ "$PLACEHOLDERS" -eq 0 ]; then
        echo "✅ PASS: No @@HOMEBREW placeholders"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "❌ FAIL: Found @@HOMEBREW placeholders"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi

    # Test 3: Test execution from temporary location
    echo ""
    echo "Test 3: Testing execution from $TEST_DIR..."
    echo "Command: $TEST_CMD"
    if OUTPUT=$($TEST_CMD 2>&1); then
        echo "$OUTPUT" | head -3
        echo ""
        echo "✅ PASS: Binary executes from temporary location"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "❌ FAIL: Binary failed to execute"
        echo "$OUTPUT" | head -10
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi

    # Test 4: Verify relative paths usage
    echo ""
    echo "Test 4: Verifying relative/system library paths..."
    if otool -L "$MAIN_BINARY" 2>/dev/null | grep -qE "@loader_path|@rpath|/usr/lib|/System"; then
        echo "✅ PASS: Using relative or system paths"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "⚠️  WARNING: No relative paths detected"
        otool -L "$MAIN_BINARY" 2>/dev/null | head -10
    fi

    # Test 5: Verify code signatures
    echo ""
    echo "Test 5: Verifying code signatures..."
    find "$BUNDLE_DIR/bin" "$BUNDLE_DIR/lib" -type f 2>/dev/null | while read -r file; do
        if file "$file" 2>/dev/null | grep -q "Mach-O"; then
            if ! codesign --verify --strict "$file" 2>/dev/null; then
                echo "  Failed: $(echo "$file" | sed "s|$BUNDLE_DIR/||")"
            fi
        fi
    done | head -10

    INVALID_SIGS="$(find "$BUNDLE_DIR/bin" "$BUNDLE_DIR/lib" -type f 2>/dev/null | while read -r file; do
        file "$file" 2>/dev/null | grep -q "Mach-O" && ! codesign --verify --strict "$file" 2>/dev/null && echo "1"
    done | wc -l)"

    if [ "$INVALID_SIGS" -eq 0 ]; then
        echo "✅ PASS: All binaries are properly signed"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "❌ FAIL: Some binaries have invalid or missing signatures"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi

    # Summary for this package
    echo ""
    echo "────────────────────────────────────────────────────────────────────"
    if [ $TESTS_FAILED -eq 0 ]; then
        echo "✅ ALL TESTS PASSED ($TESTS_PASSED/5)"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "❌ SOME TESTS FAILED ($TESTS_PASSED passed, $TESTS_FAILED failed)"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi

    ARCHIVE_SIZE=$(du -sh "$PWD/$archive" 2>/dev/null | awk '{print $1}')
    BUNDLE_SIZE=$(du -sh "$BUNDLE_DIR" 2>/dev/null | awk '{print $1}')
    echo "Archive: $archive ($ARCHIVE_SIZE)"
    echo "Bundle:  $BUNDLE_NAME ($BUNDLE_SIZE)"
    echo ""

    # Cleanup this bundle
    rm -rf "$BUNDLE_DIR"
done

echo "======================================================================"
echo "Final Summary"
echo "======================================================================"
echo "Packages tested: $((PASS_COUNT + FAIL_COUNT))"
echo "✅ Passed: $PASS_COUNT"
echo "❌ Failed: $FAIL_COUNT"
echo ""
echo "All Packages:"
find . -maxdepth 1 -name "*.tar.gz" -type f 2>/dev/null | while read -r pkg; do
    SIZE=$(du -sh "$pkg" 2>/dev/null | awk '{print $1}')
    NAME=$(basename "$pkg")
    printf "  %-30s %10s\n" "$NAME" "$SIZE"
done || echo "  No packages found"
echo ""

if [ $FAIL_COUNT -eq 0 ]; then
    echo "🎉 All packages are portable and functional!"
    exit 0
else
    echo "⚠️  Some packages have portability issues"
    exit 1
fi
