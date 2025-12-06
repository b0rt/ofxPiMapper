#!/bin/bash
################################################################################
# Packer Build Wrapper for ofxPiMapper
#
# This script wraps Packer to build a custom Raspberry Pi image using
# QEMU emulation. Works cross-platform (Linux/macOS/Windows).
#
# Usage: ./build.sh [packer options]
#
# Examples:
#   ./build.sh
#   ./build.sh --var 'rpi_username=myuser'
#   ./build.sh --var 'autostart_enabled=true'
################################################################################

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_progress() { echo -e "${BLUE}[PROGRESS]${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_SYSTEM_DIR="$(dirname "$SCRIPT_DIR")"

log_info "ofxPiMapper Packer Build System"
log_info "================================="
echo ""

################################################################################
# Check Requirements
################################################################################

log_info "Checking requirements..."

# Check for Packer
if ! command -v packer &> /dev/null; then
    log_error "Packer not found"
    log_info "Install Packer from: https://www.packer.io/downloads"
    log_info ""
    log_info "On Ubuntu/Debian:"
    log_info "  curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -"
    log_info "  sudo apt-add-repository \"deb [arch=amd64] https://apt.releases.hashicorp.com \$(lsb_release -cs) main\""
    log_info "  sudo apt-get update && sudo apt-get install packer"
    exit 1
fi

PACKER_VERSION=$(packer version | head -n1 | awk '{print $2}')
log_info "✓ Packer ${PACKER_VERSION} found"

# Check for QEMU
if ! command -v qemu-system-arm &> /dev/null && ! command -v qemu-arm-static &> /dev/null; then
    log_error "QEMU not found"
    log_info "Install QEMU:"
    log_info ""
    log_info "On Ubuntu/Debian:"
    log_info "  sudo apt-get install qemu-user-static qemu-system-arm"
    log_info ""
    log_info "On macOS:"
    log_info "  brew install qemu"
    exit 1
fi

log_info "✓ QEMU found"

# Check for packer-builder-arm plugin
log_info "Checking for packer-builder-arm plugin..."
if ! packer plugins installed 2>/dev/null | grep -q "packer-builder-arm"; then
    log_warn "packer-builder-arm plugin not found"
    log_info "Installing packer-builder-arm plugin..."

    packer plugins install github.com/mkaczanowski/arm || {
        log_error "Failed to install packer-builder-arm plugin"
        log_info "Manual installation:"
        log_info "  packer plugins install github.com/mkaczanowski/arm"
        exit 1
    }
fi

log_info "✓ packer-builder-arm plugin available"

################################################################################
# Check Disk Space
################################################################################

log_info "Checking disk space..."

AVAILABLE_SPACE=$(df "$SCRIPT_DIR" | tail -1 | awk '{print $4}')
REQUIRED_SPACE=$((30 * 1024 * 1024))  # 30 GB in KB

if [ "$AVAILABLE_SPACE" -lt "$REQUIRED_SPACE" ]; then
    log_error "Insufficient disk space"
    log_error "Required: 30 GB, Available: $(numfmt --to=iec-i --suffix=B $((AVAILABLE_SPACE * 1024)))"
    exit 1
fi

log_info "✓ Sufficient disk space: $(numfmt --to=iec-i --suffix=B $((AVAILABLE_SPACE * 1024)))"

################################################################################
# Load Configuration
################################################################################

log_info "Loading configuration..."

# Load default config
if [ -f "${BUILD_SYSTEM_DIR}/config/build.conf" ]; then
    source "${BUILD_SYSTEM_DIR}/config/build.conf"
else
    log_warn "Default configuration not found, using defaults"
fi

################################################################################
# Prepare Build Directory
################################################################################

cd "$SCRIPT_DIR"
mkdir -p deploy

log_info "Build directory: $SCRIPT_DIR"

################################################################################
# Initialize Packer
################################################################################

log_progress "Initializing Packer..."

packer init rpi4-ofxpimapper.pkr.hcl

################################################################################
# Validate Packer Template
################################################################################

log_info "Validating Packer template..."

if ! packer validate "$@" rpi4-ofxpimapper.pkr.hcl; then
    log_error "Packer template validation failed"
    exit 1
fi

log_info "✓ Template validated"

################################################################################
# Build Image
################################################################################

log_progress "Starting Packer build..."
log_warn "This will take 3-5 hours due to ARM emulation overhead"
log_info "You can monitor progress in the Packer output below"
echo ""

START_TIME=$(date +%s)

# Build with Packer, passing through any additional arguments
packer build \
    -var "rpi_username=${RPI_USERNAME:-mapper}" \
    -var "rpi_password=${RPI_PASSWORD:-projection}" \
    -var "hostname=${HOSTNAME:-ofxpimapper}" \
    -var "timezone=${TIMEZONE:-UTC}" \
    -var "of_version=${OF_VERSION:-0.12.0}" \
    -var "autostart_enabled=${AUTOSTART_ENABLED:-false}" \
    "$@" \
    rpi4-ofxpimapper.pkr.hcl

END_TIME=$(date +%s)
BUILD_DURATION=$((END_TIME - START_TIME))

################################################################################
# Post-Build Summary
################################################################################

log_info "================================================================"
log_info "Packer Build Complete!"
log_info "================================================================"
echo ""

# Find generated image
IMAGE_FILE=$(find deploy -name "*.img" -type f | head -n1)

if [ -n "$IMAGE_FILE" ]; then
    IMAGE_SIZE=$(stat -c%s "$IMAGE_FILE" 2>/dev/null || stat -f%z "$IMAGE_FILE")

    echo "Build Information:"
    echo "  - Build time: $(date -d@${BUILD_DURATION} -u +%H:%M:%S 2>/dev/null || echo ${BUILD_DURATION}s)"
    echo "  - Image: $(basename "$IMAGE_FILE")"
    echo "  - Size: $(numfmt --to=iec-i --suffix=B $IMAGE_SIZE 2>/dev/null || echo ${IMAGE_SIZE} bytes)"
    echo "  - Location: $IMAGE_FILE"
    echo ""
    echo "Next Steps:"
    echo "  1. Test in QEMU:"
    echo "     cd ../testing"
    echo "     ./test-qemu.sh $IMAGE_FILE"
    echo ""
    echo "  2. Flash to SD card:"
    echo "     sudo dd if=$IMAGE_FILE of=/dev/sdX bs=4M status=progress conv=fsync"
    echo ""
else
    log_warn "Image file not found in deploy directory"
fi

log_info "Build completed successfully!"
