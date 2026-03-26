#!/bin/bash
set -euo pipefail

# AutoSuggest Build Script
# Builds the macOS .app bundle ready to run

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
MACOS_DIR="$ROOT_DIR/macos"
BUILD_DIR="$ROOT_DIR/.build/release-app"
APP_NAME="AutoSuggest"

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

step() { echo -e "\n${CYAN}${BOLD}▸ $1${RESET}"; }
success() { echo -e "${GREEN}✓ $1${RESET}"; }
fail() { echo -e "${RED}✗ $1${RESET}"; exit 1; }

echo -e "${BOLD}"
echo "  ╔══════════════════════════════════╗"
echo "  ║     AutoSuggest Build Script     ║"
echo "  ╚══════════════════════════════════╝"
echo -e "${RESET}"

# ---------- Prerequisites ----------
step "Checking prerequisites..."

command -v swift >/dev/null 2>&1 || fail "Swift not found. Install Xcode or Command Line Tools."
SWIFT_VER=$(swift --version 2>&1 | head -1)
success "Swift: $SWIFT_VER"

if command -v xcodegen >/dev/null 2>&1; then
    HAS_XCODEGEN=true
    success "xcodegen: $(xcodegen --version 2>/dev/null || echo 'found')"
else
    HAS_XCODEGEN=false
    echo "  xcodegen not found (optional - needed for Xcode project)"
fi

# ---------- Resolve dependencies ----------
step "Resolving Swift package dependencies..."
cd "$ROOT_DIR"
swift package resolve
success "Dependencies resolved"

# ---------- Build SPM library + runner ----------
step "Building AutoSuggest (Release)..."
swift build -c release 2>&1 | tail -5
success "SPM build succeeded"

# ---------- Run tests ----------
if [[ "${SKIP_TESTS:-}" != "1" ]]; then
    step "Running tests..."
    swift test 2>&1 | tail -10
    success "All tests passed"
else
    echo "  Skipping tests (SKIP_TESTS=1)"
fi

# ---------- Build .app via xcodebuild ----------
step "Building ${APP_NAME}.app bundle..."

# Generate Xcode project if xcodegen available
if [[ "$HAS_XCODEGEN" == true ]]; then
    cd "$MACOS_DIR"
    xcodegen generate 2>&1 | head -3
    success "Xcode project generated"
fi

XCODEPROJ="$MACOS_DIR/AutoSuggestDesktop.xcodeproj"

if [[ -d "$XCODEPROJ" ]]; then
    mkdir -p "$BUILD_DIR"

    xcodebuild \
        -project "$XCODEPROJ" \
        -scheme AutoSuggestDesktop \
        -configuration Release \
        -derivedDataPath "$BUILD_DIR/DerivedData" \
        CODE_SIGN_IDENTITY="-" \
        CODE_SIGNING_REQUIRED=NO \
        CODE_SIGNING_ALLOWED=NO \
        ONLY_ACTIVE_ARCH=NO \
        2>&1 | grep -E '(BUILD|error:|warning:.*error|✗|Linking|Compiling)' | tail -20

    APP_PATH=$(find "$BUILD_DIR/DerivedData" -name "${APP_NAME}.app" -type d | head -1)

    if [[ -n "$APP_PATH" ]]; then
        # Copy to a clean location
        FINAL_APP="$BUILD_DIR/${APP_NAME}.app"
        rm -rf "$FINAL_APP"
        cp -R "$APP_PATH" "$FINAL_APP"
        success "App bundle: $FINAL_APP"
    else
        fail "Could not find ${APP_NAME}.app in build output"
    fi
else
    echo "  No .xcodeproj found. Building CLI runner instead."
    RUNNER_PATH="$ROOT_DIR/.build/release/AutoSuggestRunner"
    if [[ -f "$RUNNER_PATH" ]]; then
        success "CLI runner: $RUNNER_PATH"
        echo "  Run with: $RUNNER_PATH"
    else
        fail "Build output not found"
    fi
fi

# ---------- Summary ----------
echo ""
echo -e "${BOLD}  ╔══════════════════════════════════╗"
echo "  ║        Build Complete!           ║"
echo -e "  ╚══════════════════════════════════╝${RESET}"
echo ""

if [[ -n "${APP_PATH:-}" ]]; then
    echo -e "  ${BOLD}To run:${RESET}"
    echo "    open \"$FINAL_APP\""
    echo ""
    echo -e "  ${BOLD}To install:${RESET}"
    echo "    cp -R \"$FINAL_APP\" /Applications/"
    echo "    open /Applications/${APP_NAME}.app"
else
    echo -e "  ${BOLD}To run CLI:${RESET}"
    echo "    $ROOT_DIR/.build/release/AutoSuggestRunner"
fi

echo ""
echo -e "  ${BOLD}Note:${RESET} On first run, macOS will ask for Accessibility permissions."
echo "  Grant access in System Settings > Privacy & Security > Accessibility."
echo ""
