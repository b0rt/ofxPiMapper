#!/bin/bash
################################################################################
# QEMU Test Script for ofxPiMapper Images
#
# This script tests a Raspberry Pi image in QEMU before flashing to SD card.
#
# Usage:
#   ./test-qemu.sh <image_file> [options]
#
# Options:
#   --memory SIZE     RAM size (default: 2048M)
#   --vnc PORT        VNC port (default: 5900)
#   --ssh PORT        SSH port (default: 5022)
#   --kernel PATH     Custom kernel path
#   --dtb PATH        Custom DTB path
#   --help            Show help
#
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

################################################################################
# Configuration
################################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QEMU_CONFIG_DIR="${SCRIPT_DIR}/qemu-config"

# Default settings
MEMORY="2048M"
VNC_PORT="5900"
SSH_PORT="5022"
KERNEL_PATH=""
DTB_PATH=""
IMAGE_FILE=""

################################################################################
# Help
################################################################################

show_help() {
    cat << EOF
QEMU Test Script for ofxPiMapper Raspberry Pi Images

Usage: ./test-qemu.sh <image_file> [options]

Arguments:
    image_file          Path to the Raspberry Pi .img file to test

Options:
    --memory SIZE       RAM size (default: 2048M)
    --vnc PORT          VNC port for display (default: 5900)
    --ssh PORT          SSH port forwarding (default: 5022)
    --kernel PATH       Custom kernel path (auto-download if not specified)
    --dtb PATH          Custom DTB path (auto-download if not specified)
    --help              Show this help message

Examples:
    # Basic test
    ./test-qemu.sh ../pi-gen-method/deploy/image.img

    # Test with more memory and custom VNC port
    ./test-qemu.sh image.img --memory 4096M --vnc 5901

    # Test with SSH on different port
    ./test-qemu.sh image.img --ssh 2222

Access the running system:
    - VNC:  vncviewer localhost:5900 (or your specified port)
    - SSH:  ssh -p 5022 mapper@localhost (use your configured username/port)

Press Ctrl+C to stop QEMU
EOF
}

################################################################################
# Parse Arguments
################################################################################

if [ $# -eq 0 ]; then
    show_help
    exit 1
fi

# First argument is the image file
IMAGE_FILE="$1"
shift

while [[ $# -gt 0 ]]; do
    case $1 in
        --memory)
            MEMORY="$2"
            shift 2
            ;;
        --vnc)
            VNC_PORT="$2"
            shift 2
            ;;
        --ssh)
            SSH_PORT="$2"
            shift 2
            ;;
        --kernel)
            KERNEL_PATH="$2"
            shift 2
            ;;
        --dtb)
            DTB_PATH="$2"
            shift 2
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

################################################################################
# Validate Image File
################################################################################

if [ ! -f "$IMAGE_FILE" ]; then
    log_error "Image file not found: $IMAGE_FILE"
    exit 1
fi

IMAGE_FILE=$(realpath "$IMAGE_FILE")
IMAGE_SIZE=$(stat -c%s "$IMAGE_FILE" 2>/dev/null || stat -f%z "$IMAGE_FILE")

log_info "Testing image: $(basename "$IMAGE_FILE")"
log_info "Image size: $(numfmt --to=iec-i --suffix=B $IMAGE_SIZE 2>/dev/null || echo ${IMAGE_SIZE} bytes)"

################################################################################
# Check Requirements
################################################################################

log_info "Checking requirements..."

# Check for QEMU
if ! command -v qemu-system-arm &> /dev/null && ! command -v qemu-system-aarch64 &> /dev/null; then
    log_error "QEMU not found"
    log_info "Install QEMU:"
    log_info ""
    log_info "On Ubuntu/Debian:"
    log_info "  sudo apt-get install qemu-system-arm qemu-system-misc"
    log_info ""
    log_info "On macOS:"
    log_info "  brew install qemu"
    exit 1
fi

QEMU_ARM=$(command -v qemu-system-arm)
log_info "✓ QEMU found: $QEMU_ARM"

################################################################################
# Download Kernel and DTB if Not Provided
################################################################################

mkdir -p "$QEMU_CONFIG_DIR"

if [ -z "$KERNEL_PATH" ]; then
    log_info "Downloading Raspberry Pi kernel for QEMU..."

    KERNEL_URL="https://github.com/dhruvvyas90/qemu-rpi-kernel/raw/master/kernel-qemu-5.10.63-buster"
    KERNEL_PATH="${QEMU_CONFIG_DIR}/kernel-qemu"

    if [ ! -f "$KERNEL_PATH" ]; then
        wget -q --show-progress -O "$KERNEL_PATH" "$KERNEL_URL" || {
            log_error "Failed to download kernel"
            exit 1
        }
    fi

    log_info "✓ Kernel: $KERNEL_PATH"
fi

if [ -z "$DTB_PATH" ]; then
    log_info "Downloading Raspberry Pi DTB for QEMU..."

    DTB_URL="https://github.com/dhruvvyas90/qemu-rpi-kernel/raw/master/versatile-pb-buster-5.10.63.dtb"
    DTB_PATH="${QEMU_CONFIG_DIR}/versatile-pb.dtb"

    if [ ! -f "$DTB_PATH" ]; then
        wget -q --show-progress -O "$DTB_PATH" "$DTB_URL" || {
            log_error "Failed to download DTB"
            exit 1
        }
    fi

    log_info "✓ DTB: $DTB_PATH"
fi

################################################################################
# Prepare Image for QEMU
################################################################################

log_info "Preparing image for QEMU..."

# Extract boot partition information
BOOT_OFFSET=$(fdisk -l "$IMAGE_FILE" | grep "${IMAGE_FILE}1" | awk '{print $2}')
ROOT_OFFSET=$(fdisk -l "$IMAGE_FILE" | grep "${IMAGE_FILE}2" | awk '{print $2}')

if [ -z "$ROOT_OFFSET" ]; then
    log_error "Could not determine partition offsets"
    exit 1
fi

BYTE_OFFSET=$((ROOT_OFFSET * 512))

log_info "✓ Root partition offset: $BYTE_OFFSET bytes"

################################################################################
# Configure VNC Display
################################################################################

VNC_DISPLAY=$((VNC_PORT - 5900))

log_info "VNC display will be available on port $VNC_PORT (display :${VNC_DISPLAY})"

################################################################################
# Start QEMU
################################################################################

log_progress "Starting QEMU..."
log_info ""
log_info "================================================================"
log_info "QEMU Raspberry Pi Emulator"
log_info "================================================================"
log_info "Configuration:"
log_info "  - Memory: $MEMORY"
log_info "  - VNC Port: $VNC_PORT (connect with: vncviewer localhost:$VNC_PORT)"
log_info "  - SSH Port: $SSH_PORT (connect with: ssh -p $SSH_PORT mapper@localhost)"
log_info "  - Image: $(basename "$IMAGE_FILE")"
log_info ""
log_info "Access Methods:"
log_info "  1. VNC:   vncviewer localhost:$VNC_PORT"
log_info "  2. SSH:   ssh -p $SSH_PORT mapper@localhost"
log_info ""
log_warn "Boot may take 2-3 minutes. Be patient!"
log_warn "First boot may take longer as the system initializes."
log_info ""
log_info "Press Ctrl+C to stop QEMU"
log_info "================================================================"
echo ""

# QEMU command
$QEMU_ARM \
    -kernel "$KERNEL_PATH" \
    -cpu arm1176 \
    -m "$MEMORY" \
    -M versatilepb \
    -dtb "$DTB_PATH" \
    -no-reboot \
    -serial stdio \
    -append "root=/dev/sda2 panic=1 rootfstype=ext4 rw" \
    -drive "file=${IMAGE_FILE},format=raw" \
    -net nic \
    -net user,hostfwd=tcp::${SSH_PORT}-:22 \
    -vnc ":${VNC_DISPLAY}"

log_info "QEMU stopped"
