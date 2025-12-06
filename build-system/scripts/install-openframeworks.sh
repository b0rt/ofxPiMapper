#!/bin/bash
################################################################################
# Install openFrameworks for Raspberry Pi
#
# This script downloads, installs, and configures openFrameworks for use with
# ofxPiMapper on Raspberry Pi.
#
# Usage: ./install-openframeworks.sh [target_user]
################################################################################

set -e  # Exit on error
set -u  # Exit on undefined variable

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_progress() {
    echo -e "${BLUE}[PROGRESS]${NC} $1"
}

################################################################################
# Configuration
################################################################################

# Target user (defaults to current user or first argument)
TARGET_USER="${1:-${RPI_USERNAME:-$(whoami)}}"

# openFrameworks settings
OF_VERSION="${OF_VERSION:-0.12.0}"
OF_PLATFORM="${OF_PLATFORM:-linuxarmv7l}"
OF_DOWNLOAD_URL="${OF_DOWNLOAD_URL:-https://github.com/openframeworks/openFrameworks/releases/download/${OF_VERSION}/of_v${OF_VERSION}_${OF_PLATFORM}_release.tar.gz}"
OF_ROOT="${OF_ROOT:-/home/${TARGET_USER}/openFrameworks}"

# Number of parallel jobs
PARALLEL_JOBS="${PARALLEL_JOBS:-$(nproc 2>/dev/null || echo 2)}"

log_info "Installing openFrameworks ${OF_VERSION} for ${TARGET_USER}"
log_info "Platform: ${OF_PLATFORM}"
log_info "Installation directory: ${OF_ROOT}"
log_info "Parallel jobs: ${PARALLEL_JOBS}"

################################################################################
# Download openFrameworks
################################################################################

DOWNLOAD_DIR="/tmp/of_download_$$"
mkdir -p "$DOWNLOAD_DIR"

log_progress "Downloading openFrameworks ${OF_VERSION}..."
log_info "URL: ${OF_DOWNLOAD_URL}"

if ! wget -q --show-progress -O "${DOWNLOAD_DIR}/of.tar.gz" "${OF_DOWNLOAD_URL}"; then
    log_error "Failed to download openFrameworks"
    log_info "Trying alternative download method..."

    # Try curl as fallback
    if ! curl -L -o "${DOWNLOAD_DIR}/of.tar.gz" "${OF_DOWNLOAD_URL}"; then
        log_error "Download failed with both wget and curl"
        rm -rf "$DOWNLOAD_DIR"
        exit 1
    fi
fi

################################################################################
# Verify Download
################################################################################

log_info "Verifying download..."

if [ ! -f "${DOWNLOAD_DIR}/of.tar.gz" ]; then
    log_error "Downloaded file not found"
    rm -rf "$DOWNLOAD_DIR"
    exit 1
fi

FILE_SIZE=$(stat -c%s "${DOWNLOAD_DIR}/of.tar.gz" 2>/dev/null || stat -f%z "${DOWNLOAD_DIR}/of.tar.gz")
if [ "$FILE_SIZE" -lt 10000000 ]; then
    log_error "Downloaded file is too small (${FILE_SIZE} bytes), download may have failed"
    rm -rf "$DOWNLOAD_DIR"
    exit 1
fi

log_info "Download complete ($(numfmt --to=iec-i --suffix=B $FILE_SIZE))"

################################################################################
# Extract openFrameworks
################################################################################

log_progress "Extracting openFrameworks..."

# Create parent directory
PARENT_DIR=$(dirname "$OF_ROOT")
mkdir -p "$PARENT_DIR"

# Extract to temporary location first
EXTRACT_DIR="${DOWNLOAD_DIR}/of_extracted"
mkdir -p "$EXTRACT_DIR"

tar -xzf "${DOWNLOAD_DIR}/of.tar.gz" -C "$EXTRACT_DIR"

# Find the extracted directory (it should be of_v0.xx.x_platform_release)
OF_EXTRACTED=$(find "$EXTRACT_DIR" -maxdepth 1 -type d -name "of_v*" | head -n1)

if [ -z "$OF_EXTRACTED" ]; then
    log_error "Could not find extracted openFrameworks directory"
    rm -rf "$DOWNLOAD_DIR"
    exit 1
fi

# Move to final location
log_info "Moving to ${OF_ROOT}..."
if [ -d "$OF_ROOT" ]; then
    log_warn "Removing existing openFrameworks installation at ${OF_ROOT}"
    rm -rf "$OF_ROOT"
fi

mv "$OF_EXTRACTED" "$OF_ROOT"

# Clean up download directory
rm -rf "$DOWNLOAD_DIR"

################################################################################
# Set Ownership
################################################################################

log_info "Setting ownership to ${TARGET_USER}..."
chown -R "${TARGET_USER}:${TARGET_USER}" "$OF_ROOT"

################################################################################
# Install Additional Dependencies via oF Scripts
################################################################################

log_progress "Running openFrameworks dependency installation scripts..."

# Change to OF scripts directory
cd "${OF_ROOT}/scripts/linux"

# Run the install scripts as the target user
if [ -f "install_dependencies.sh" ]; then
    log_info "Running install_dependencies.sh..."
    sudo -u "$TARGET_USER" bash install_dependencies.sh -y || log_warn "Some dependencies may have failed"
else
    log_warn "install_dependencies.sh not found, skipping"
fi

################################################################################
# Compile openFrameworks Core
################################################################################

log_progress "Compiling openFrameworks core libraries..."
log_info "This may take 30-60 minutes depending on your hardware..."

cd "${OF_ROOT}/libs/openFrameworksCompiled/project"

# Clean any previous builds
sudo -u "$TARGET_USER" make clean || true

# Compile with progress indicator
log_info "Compiling with ${PARALLEL_JOBS} parallel jobs..."

if sudo -u "$TARGET_USER" make -j${PARALLEL_JOBS} 2>&1 | tee /tmp/of_compile.log; then
    log_info "openFrameworks core compiled successfully!"
else
    log_error "openFrameworks compilation failed. Check /tmp/of_compile.log for details"
    tail -n 50 /tmp/of_compile.log
    exit 1
fi

################################################################################
# Verify Installation
################################################################################

log_progress "Verifying openFrameworks installation..."

VERIFICATION_FAILED=0

# Check for critical files and directories
CRITICAL_PATHS=(
    "${OF_ROOT}/libs/openFrameworksCompiled/lib/${OF_PLATFORM}/libopenFrameworks.a"
    "${OF_ROOT}/addons"
    "${OF_ROOT}/apps"
    "${OF_ROOT}/examples"
)

for path in "${CRITICAL_PATHS[@]}"; do
    if [ ! -e "$path" ]; then
        log_error "Critical path not found: $path"
        VERIFICATION_FAILED=1
    fi
done

if [ $VERIFICATION_FAILED -eq 1 ]; then
    log_error "openFrameworks installation verification failed"
    exit 1
fi

################################################################################
# Test Compilation with Empty Example
################################################################################

log_progress "Testing openFrameworks with empty example..."

cd "${OF_ROOT}/apps/myApps"

# Create a test application
TEST_APP_NAME="testOF_$$"
sudo -u "$TARGET_USER" "${OF_ROOT}/scripts/linux/createProject.sh" -p "$TEST_APP_NAME" || true

if [ -d "$TEST_APP_NAME" ]; then
    cd "$TEST_APP_NAME"

    log_info "Compiling test application..."
    if sudo -u "$TARGET_USER" make -j${PARALLEL_JOBS} 2>&1 | tee /tmp/of_test_compile.log; then
        log_info "Test compilation successful!"
    else
        log_warn "Test compilation failed, but continuing anyway"
        log_info "Check /tmp/of_test_compile.log for details"
    fi

    # Clean up test app
    cd ..
    rm -rf "$TEST_APP_NAME"
else
    log_warn "Could not create test application, skipping test compilation"
fi

################################################################################
# Configure Default Addons Directory
################################################################################

log_info "Setting up addons directory..."

ADDONS_DIR="${OF_ROOT}/addons"
mkdir -p "$ADDONS_DIR"
chown "${TARGET_USER}:${TARGET_USER}" "$ADDONS_DIR"

################################################################################
# Create Useful Scripts
################################################################################

log_info "Creating helper scripts..."

# Create a script to easily create new projects
cat > "${OF_ROOT}/new-project.sh" <<'EOFSCRIPT'
#!/bin/bash
# Helper script to create new openFrameworks projects

if [ -z "$1" ]; then
    echo "Usage: ./new-project.sh <project_name>"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"${SCRIPT_DIR}/scripts/linux/createProject.sh" -p "$1"
EOFSCRIPT

chmod +x "${OF_ROOT}/new-project.sh"
chown "${TARGET_USER}:${TARGET_USER}" "${OF_ROOT}/new-project.sh"

# Create environment setup script
cat > "${OF_ROOT}/setup-env.sh" <<EOFSCRIPT
#!/bin/bash
# Source this file to set up openFrameworks environment variables

export OF_ROOT="${OF_ROOT}"
export PKG_CONFIG_PATH="\${OF_ROOT}/libs/openFrameworksCompiled/lib/pkgconfig:\${PKG_CONFIG_PATH}"
export LD_LIBRARY_PATH="\${OF_ROOT}/libs/openFrameworksCompiled/lib/${OF_PLATFORM}:\${LD_LIBRARY_PATH}"

echo "openFrameworks environment configured:"
echo "  OF_ROOT=\${OF_ROOT}"
EOFSCRIPT

chmod +x "${OF_ROOT}/setup-env.sh"
chown "${TARGET_USER}:${TARGET_USER}" "${OF_ROOT}/setup-env.sh"

################################################################################
# Add to User's Profile
################################################################################

USER_HOME="/home/${TARGET_USER}"
BASHRC="${USER_HOME}/.bashrc"

if [ -f "$BASHRC" ]; then
    log_info "Adding openFrameworks to ${TARGET_USER}'s .bashrc..."

    # Remove any existing OF_ROOT exports
    sed -i '/export OF_ROOT=/d' "$BASHRC"

    # Add new export
    cat >> "$BASHRC" <<EOF

# openFrameworks environment
export OF_ROOT="${OF_ROOT}"
EOF

    chown "${TARGET_USER}:${TARGET_USER}" "$BASHRC"
fi

################################################################################
# Print Summary
################################################################################

log_info "================================================================"
log_info "openFrameworks Installation Complete!"
log_info "================================================================"
echo ""
echo "Installation Details:"
echo "  - Version: ${OF_VERSION}"
echo "  - Platform: ${OF_PLATFORM}"
echo "  - Location: ${OF_ROOT}"
echo "  - User: ${TARGET_USER}"
echo ""
echo "Core library:"
if [ -f "${OF_ROOT}/libs/openFrameworksCompiled/lib/${OF_PLATFORM}/libopenFrameworks.a" ]; then
    LIB_SIZE=$(stat -c%s "${OF_ROOT}/libs/openFrameworksCompiled/lib/${OF_PLATFORM}/libopenFrameworks.a" 2>/dev/null || stat -f%z "${OF_ROOT}/libs/openFrameworksCompiled/lib/${OF_PLATFORM}/libopenFrameworks.a")
    echo "  ✓ libopenFrameworks.a ($(numfmt --to=iec-i --suffix=B $LIB_SIZE))"
else
    echo "  ✗ libopenFrameworks.a NOT FOUND"
fi
echo ""
echo "Useful commands:"
echo "  - Create new project: cd ${OF_ROOT} && ./new-project.sh myProject"
echo "  - Setup environment: source ${OF_ROOT}/setup-env.sh"
echo ""
log_info "You can now proceed to install ofxPiMapper and other addons."
