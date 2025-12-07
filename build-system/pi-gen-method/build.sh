#!/bin/bash
################################################################################
# ofxPiMapper Pi-Gen Build Script
#
# This script uses pi-gen (official Raspberry Pi image builder) to create
# a custom Raspberry Pi OS image with ofxPiMapper pre-installed.
#
# Usage:
#   sudo ./build.sh [options]
#
# Options:
#   --docker              Build using Docker (recommended)
#   --config FILE         Use custom configuration file
#   --clean               Clean previous builds before starting
#   --stage STAGE         Build only up to specified stage
#   --help                Show this help message
#
################################################################################

set -e  # Exit on error
set -u  # Exit on undefined variable

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
# Script Configuration
################################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_SYSTEM_DIR="$(dirname "$SCRIPT_DIR")"
PIGEN_DIR="${SCRIPT_DIR}/pi-gen"
DEPLOY_DIR="${SCRIPT_DIR}/deploy"

# Default options
USE_DOCKER=false
CLEAN_BUILD=false
CUSTOM_CONFIG=""
BUILD_STAGE=""

################################################################################
# Parse Arguments
################################################################################

show_help() {
    cat << EOF
ofxPiMapper Pi-Gen Build Script

Usage: sudo ./build.sh [options]

Options:
    --docker              Build using Docker (recommended, no root needed)
    --config FILE         Use custom configuration file
    --clean               Clean previous builds before starting
    --stage STAGE         Build only up to specified stage (e.g., stage3)
    --help                Show this help message

Examples:
    # Basic build (requires Linux host)
    sudo ./build.sh

    # Build with Docker
    ./build.sh --docker

    # Build with custom configuration
    sudo ./build.sh --config ../../config/user.conf

    # Clean build with Docker
    ./build.sh --docker --clean

For more information, see: ../README.md
EOF
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --docker)
            USE_DOCKER=true
            shift
            ;;
        --config)
            CUSTOM_CONFIG="$2"
            shift 2
            ;;
        --clean)
            CLEAN_BUILD=true
            shift
            ;;
        --stage)
            BUILD_STAGE="$2"
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
# Load Configuration
################################################################################

log_info "Loading build configuration..."

# Load default configuration
if [ -f "${BUILD_SYSTEM_DIR}/config/build.conf" ]; then
    source "${BUILD_SYSTEM_DIR}/config/build.conf"
else
    log_error "Default configuration not found: ${BUILD_SYSTEM_DIR}/config/build.conf"
    exit 1
fi

# Load custom configuration if specified
if [ -n "$CUSTOM_CONFIG" ]; then
    if [ -f "$CUSTOM_CONFIG" ]; then
        log_info "Loading custom configuration: $CUSTOM_CONFIG"
        source "$CUSTOM_CONFIG"
    else
        log_error "Custom configuration not found: $CUSTOM_CONFIG"
        exit 1
    fi
fi

log_info "Configuration loaded successfully"

################################################################################
# Check Requirements
################################################################################

log_info "Checking system requirements..."

if [ "$USE_DOCKER" = false ]; then
    # Check for root when not using Docker
    if [ "$EUID" -ne 0 ]; then
        log_error "Please run as root (use sudo) or use --docker flag"
        exit 1
    fi

    # Check for required packages
    REQUIRED_PACKAGES=(
        "git" "curl" "quilt" "parted" "qemu-user-static"
        "debootstrap" "zerofree" "zip" "dosfstools"
        "libarchive-tools" "libcap2-bin" "grep" "rsync"
        "xz-utils" "file" "bc" "qemu-utils" "kpartx"
    )

    MISSING_PACKAGES=()
    for pkg in "${REQUIRED_PACKAGES[@]}"; do
        if ! dpkg -l | grep -q "^ii  $pkg "; then
            MISSING_PACKAGES+=("$pkg")
        fi
    done

    if [ ${#MISSING_PACKAGES[@]} -ne 0 ]; then
        log_error "Missing required packages: ${MISSING_PACKAGES[*]}"
        log_info "Install with: sudo apt-get install ${MISSING_PACKAGES[*]}"
        exit 1
    fi
else
    # Check for Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker not found. Please install Docker first."
        log_info "Visit: https://docs.docker.com/get-docker/"
        exit 1
    fi
fi

################################################################################
# Check Disk Space
################################################################################

AVAILABLE_SPACE=$(df "$SCRIPT_DIR" | tail -1 | awk '{print $4}')
REQUIRED_SPACE=$((25 * 1024 * 1024))  # 25 GB in KB

if [ "$AVAILABLE_SPACE" -lt "$REQUIRED_SPACE" ]; then
    log_error "Insufficient disk space"
    log_error "Required: 25 GB, Available: $(numfmt --to=iec-i --suffix=B $((AVAILABLE_SPACE * 1024)))"
    exit 1
fi

log_info "✓ Disk space sufficient: $(numfmt --to=iec-i --suffix=B $((AVAILABLE_SPACE * 1024)))"

################################################################################
# Clean Previous Builds
################################################################################

if [ "$CLEAN_BUILD" = true ]; then
    log_warn "Cleaning previous builds..."

    if [ -d "$PIGEN_DIR" ]; then
        cd "$PIGEN_DIR"
        if [ "$USE_DOCKER" = true ]; then
            ./docker_clean.sh || true
        else
            ./clean.sh || true
        fi
    fi

    rm -rf "${DEPLOY_DIR}"/*
    log_info "✓ Clean complete"
fi

################################################################################
# Clone/Update pi-gen
################################################################################

log_progress "Setting up pi-gen..."

if [ -d "$PIGEN_DIR" ]; then
    log_info "Updating existing pi-gen repository..."
    cd "$PIGEN_DIR"
    git fetch origin
else
    log_info "Cloning pi-gen repository..."
    git clone https://github.com/RPi-Distro/pi-gen.git "$PIGEN_DIR"
    cd "$PIGEN_DIR"
fi

# Determine which branch to use based on RPI_OS_RELEASE
# This ensures GPG keys and repository configuration match the target release
PIGEN_BRANCH="master"
case "${RPI_OS_RELEASE}" in
    bookworm|bullseye)
        # Check if the release-specific branch exists
        if git ls-remote --heads origin "${RPI_OS_RELEASE}" | grep -q "${RPI_OS_RELEASE}"; then
            PIGEN_BRANCH="${RPI_OS_RELEASE}"
            log_info "Using pi-gen branch '${PIGEN_BRANCH}' for ${RPI_OS_RELEASE} release"
        else
            log_warn "Branch '${RPI_OS_RELEASE}' not found, using master branch"
            log_warn "This may cause GPG signature verification issues"
        fi
        ;;
    *)
        log_info "Using pi-gen master branch for ${RPI_OS_RELEASE} release"
        ;;
esac

# Checkout the appropriate branch
git checkout "${PIGEN_BRANCH}"
git pull origin "${PIGEN_BRANCH}"

PIGEN_COMMIT=$(git rev-parse --short HEAD)
log_info "Using pi-gen commit: $PIGEN_COMMIT (branch: $PIGEN_BRANCH)"

################################################################################
# Configure pi-gen
################################################################################

log_info "Configuring pi-gen..."

# Create pi-gen config file
cat > "${PIGEN_DIR}/config" <<EOF
# ofxPiMapper pi-gen configuration
IMG_NAME="ofxpimapper-rpi4"
RELEASE="${RPI_OS_RELEASE}"
DEPLOY_ZIP=1
LOCALE_DEFAULT="${LOCALE}"
TARGET_HOSTNAME="${HOSTNAME}"
KEYBOARD_KEYMAP="${KEYBOARD_LAYOUT}"
KEYBOARD_LAYOUT="${KEYBOARD_LAYOUT}"
TIMEZONE_DEFAULT="${TIMEZONE}"
FIRST_USER_NAME="${RPI_USERNAME}"
FIRST_USER_PASS="${RPI_PASSWORD}"
ENABLE_SSH="${ENABLE_SSH}"
STAGE_LIST="stage0 stage1 stage2 stage3"
EOF

# Determine which base stages to include
if [ "$BASE_IMAGE" = "desktop" ]; then
    # Include desktop environment
    sed -i 's/STAGE_LIST=.*/STAGE_LIST="stage0 stage1 stage2 stage3"/' "${PIGEN_DIR}/config"
else
    # Lite version (no desktop)
    sed -i 's/STAGE_LIST=.*/STAGE_LIST="stage0 stage1 stage3"/' "${PIGEN_DIR}/config"
fi

log_info "✓ pi-gen configured"

################################################################################
# Create Custom ofxPiMapper Stage
################################################################################

log_progress "Creating custom ofxPiMapper installation stage..."

STAGE_DIR="${PIGEN_DIR}/stage3"
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"

# Create prerun script
cat > "${STAGE_DIR}/prerun.sh" <<'EOF'
#!/bin/bash
echo "Starting ofxPiMapper custom stage (stage3)..."
EOF

chmod +x "${STAGE_DIR}/prerun.sh"

# Stage 00: System Dependencies
mkdir -p "${STAGE_DIR}/00-install-dependencies"

cat > "${STAGE_DIR}/00-install-dependencies/00-run-chroot.sh" <<'EOFRUN'
#!/bin/bash -e
# Install system dependencies

################################################################################
# Update System
################################################################################

echo "[INFO] Updating package lists..."
apt-get update -y

echo "[INFO] Upgrading existing packages..."
apt-get upgrade -y

################################################################################
# Install Build Essentials
################################################################################

echo "[INFO] Installing build essentials..."
apt-get install -y \
    build-essential \
    git \
    cmake \
    pkg-config \
    gdb \
    ccache

################################################################################
# Install OpenGL and Graphics Libraries
################################################################################

echo "[INFO] Installing OpenGL ES and graphics libraries..."
apt-get install -y \
    libgles2-mesa-dev \
    libglfw3-dev \
    libegl1-mesa-dev \
    mesa-utils \
    libdrm-dev \
    libgbm-dev

################################################################################
# Install GStreamer (Required for video playback)
################################################################################

echo "[INFO] Installing GStreamer and plugins..."
apt-get install -y \
    libgstreamer1.0-dev \
    libgstreamer-plugins-base1.0-dev \
    libgstreamer-plugins-good1.0-dev \
    libgstreamer-plugins-bad1.0-dev \
    gstreamer1.0-plugins-base \
    gstreamer1.0-plugins-good \
    gstreamer1.0-plugins-bad \
    gstreamer1.0-plugins-ugly \
    gstreamer1.0-libav \
    gstreamer1.0-alsa \
    gstreamer1.0-tools

################################################################################
# Install Audio Libraries
################################################################################

echo "[INFO] Installing audio libraries..."
apt-get install -y \
    libasound2-dev \
    libpulse-dev \
    alsa-utils \
    pulseaudio \
    libmpg123-dev \
    libsndfile1-dev \
    libfreeimage-dev

################################################################################
# Install Additional Libraries
################################################################################

echo "[INFO] Installing additional required libraries..."
apt-get install -y \
    libfreetype6-dev \
    libfontconfig1-dev \
    libcairo2-dev \
    libglm-dev \
    libxrandr-dev \
    libxi-dev \
    libxcursor-dev \
    libxinerama-dev \
    libxxf86vm-dev \
    libxmu-dev \
    libudev-dev \
    libboost-all-dev \
    libssl-dev \
    libpoco-dev \
    libpugixml-dev \
    libgtk-3-dev \
    libjpeg-dev \
    libpng-dev \
    libtiff-dev \
    libavcodec-dev \
    libavformat-dev \
    libswscale-dev \
    libv4l-dev \
    libxvidcore-dev \
    libx264-dev

################################################################################
# Install Utilities
################################################################################

echo "[INFO] Installing utilities..."
apt-get install -y \
    curl \
    wget \
    unzip \
    rsync \
    htop \
    vim \
    nano \
    screen \
    tmux \
    net-tools \
    wireless-tools

################################################################################
# Install Python (for some oF scripts)
################################################################################

echo "[INFO] Installing Python..."
apt-get install -y \
    python3 \
    python3-pip \
    python3-dev

################################################################################
# Clean up
################################################################################

echo "[INFO] Cleaning up..."
apt-get autoremove -y
apt-get autoclean -y

echo "[INFO] Dependency installation completed successfully!"
EOFRUN

chmod +x "${STAGE_DIR}/00-install-dependencies/00-run-chroot.sh"

# Stage 00a: Configure Wireless and Bluetooth
mkdir -p "${STAGE_DIR}/00a-configure-wireless-bluetooth"

cat > "${STAGE_DIR}/00a-configure-wireless-bluetooth/00-run.sh" <<'EOFRUN'
#!/bin/bash -e
# Copy configure-wireless-bluetooth script to rootfs
install -m 755 -D files/configure-wireless-bluetooth.sh "${ROOTFS_DIR}/tmp/configure-wireless-bluetooth.sh"
EOFRUN

mkdir -p "${STAGE_DIR}/00a-configure-wireless-bluetooth/files"
cp "${BUILD_SYSTEM_DIR}/scripts/configure-wireless-bluetooth.sh" \
   "${STAGE_DIR}/00a-configure-wireless-bluetooth/files/configure-wireless-bluetooth.sh"

cat > "${STAGE_DIR}/00a-configure-wireless-bluetooth/00-run-chroot.sh" <<'EOFRUN'
#!/bin/bash -e
bash /tmp/configure-wireless-bluetooth.sh
EOFRUN

chmod +x "${STAGE_DIR}/00a-configure-wireless-bluetooth/00-run.sh"
chmod +x "${STAGE_DIR}/00a-configure-wireless-bluetooth/00-run-chroot.sh"

# Stage 01: Configure X11
mkdir -p "${STAGE_DIR}/01-configure-x11"

cat > "${STAGE_DIR}/01-configure-x11/00-run.sh" <<'EOFRUN'
#!/bin/bash -e
# Copy configure-x11 script to rootfs
install -m 755 -D files/configure-x11.sh "${ROOTFS_DIR}/tmp/configure-x11.sh"
EOFRUN

mkdir -p "${STAGE_DIR}/01-configure-x11/files"
cp "${BUILD_SYSTEM_DIR}/scripts/configure-x11.sh" \
   "${STAGE_DIR}/01-configure-x11/files/configure-x11.sh"

cat > "${STAGE_DIR}/01-configure-x11/00-run-chroot.sh" <<'EOFRUN'
#!/bin/bash -e
bash /tmp/configure-x11.sh
EOFRUN

chmod +x "${STAGE_DIR}/01-configure-x11/00-run.sh"
chmod +x "${STAGE_DIR}/01-configure-x11/00-run-chroot.sh"

# Stage 02: Configure Auto-login
mkdir -p "${STAGE_DIR}/02-configure-autologin"

cat > "${STAGE_DIR}/02-configure-autologin/00-run.sh" <<'EOFRUN'
#!/bin/bash -e
# Copy configure-autologin script to rootfs
install -m 755 -D files/configure-autologin.sh "${ROOTFS_DIR}/tmp/configure-autologin.sh"
EOFRUN

mkdir -p "${STAGE_DIR}/02-configure-autologin/files"
cp "${BUILD_SYSTEM_DIR}/scripts/configure-autologin.sh" \
   "${STAGE_DIR}/02-configure-autologin/files/configure-autologin.sh"

cat > "${STAGE_DIR}/02-configure-autologin/00-run-chroot.sh" <<'EOFRUN'
#!/bin/bash -e
bash /tmp/configure-autologin.sh
EOFRUN

chmod +x "${STAGE_DIR}/02-configure-autologin/00-run.sh"
chmod +x "${STAGE_DIR}/02-configure-autologin/00-run-chroot.sh"

# Stage 03: Install openFrameworks
mkdir -p "${STAGE_DIR}/03-install-openframeworks"

cat > "${STAGE_DIR}/03-install-openframeworks/00-run.sh" <<'EOFRUN'
#!/bin/bash -e
# Copy install-openframeworks script to rootfs
install -m 755 -D files/install-openframeworks.sh "${ROOTFS_DIR}/tmp/install-openframeworks.sh"
EOFRUN

mkdir -p "${STAGE_DIR}/03-install-openframeworks/files"
cp "${BUILD_SYSTEM_DIR}/scripts/install-openframeworks.sh" \
   "${STAGE_DIR}/03-install-openframeworks/files/install-openframeworks.sh"

cat > "${STAGE_DIR}/03-install-openframeworks/00-run-chroot.sh" <<'EOFRUN'
#!/bin/bash -e
bash /tmp/install-openframeworks.sh
EOFRUN

chmod +x "${STAGE_DIR}/03-install-openframeworks/00-run.sh"
chmod +x "${STAGE_DIR}/03-install-openframeworks/00-run-chroot.sh"

# Stage 04: Install ofxPiMapper
mkdir -p "${STAGE_DIR}/04-install-ofxpimapper"

cat > "${STAGE_DIR}/04-install-ofxpimapper/00-run.sh" <<'EOFRUN'
#!/bin/bash -e
# Copy install-ofxpimapper script to rootfs
install -m 755 -D files/install-ofxpimapper.sh "${ROOTFS_DIR}/tmp/install-ofxpimapper.sh"
EOFRUN

mkdir -p "${STAGE_DIR}/04-install-ofxpimapper/files"
cp "${BUILD_SYSTEM_DIR}/scripts/install-ofxpimapper.sh" \
   "${STAGE_DIR}/04-install-ofxpimapper/files/install-ofxpimapper.sh"

cat > "${STAGE_DIR}/04-install-ofxpimapper/00-run-chroot.sh" <<'EOFRUN'
#!/bin/bash -e
bash /tmp/install-ofxpimapper.sh
EOFRUN

chmod +x "${STAGE_DIR}/04-install-ofxpimapper/00-run.sh"
chmod +x "${STAGE_DIR}/04-install-ofxpimapper/00-run-chroot.sh"

# Stage 05: Configure Auto-start
if [ "${AUTOSTART_ENABLED}" = "true" ]; then
    mkdir -p "${STAGE_DIR}/05-configure-autostart"

    cat > "${STAGE_DIR}/05-configure-autostart/00-run.sh" <<'EOFRUN'
#!/bin/bash -e
# Copy configure-autostart script to rootfs
install -m 755 -D files/configure-autostart.sh "${ROOTFS_DIR}/tmp/configure-autostart.sh"
EOFRUN

    mkdir -p "${STAGE_DIR}/05-configure-autostart/files"
    cp "${BUILD_SYSTEM_DIR}/scripts/configure-autostart.sh" \
       "${STAGE_DIR}/05-configure-autostart/files/configure-autostart.sh"

    cat > "${STAGE_DIR}/05-configure-autostart/00-run-chroot.sh" <<'EOFRUN'
#!/bin/bash -e
bash /tmp/configure-autostart.sh
EOFRUN

    chmod +x "${STAGE_DIR}/05-configure-autostart/00-run.sh"
    chmod +x "${STAGE_DIR}/05-configure-autostart/00-run-chroot.sh"
fi

log_info "✓ Custom stage created"

################################################################################
# Start Build
################################################################################

log_progress "Starting image build..."
log_info "This will take 2-4 hours depending on your hardware"
log_info "Build log: ${PIGEN_DIR}/work/*/build.log"

cd "$PIGEN_DIR"

# Create deploy directory
mkdir -p "$DEPLOY_DIR"

START_TIME=$(date +%s)

if [ "$USE_DOCKER" = true ]; then
    log_info "Building with Docker..."
    ./build-docker.sh
else
    log_info "Building on host system..."
    ./build.sh
fi

END_TIME=$(date +%s)
BUILD_DURATION=$((END_TIME - START_TIME))

################################################################################
# Post-Build Processing
################################################################################

log_progress "Processing build artifacts..."

# Move images to deploy directory
if [ -d "${PIGEN_DIR}/deploy" ]; then
    mv "${PIGEN_DIR}/deploy"/* "$DEPLOY_DIR/" || true
fi

# Find the generated image
IMAGE_FILE=$(find "$DEPLOY_DIR" -name "*.img" -type f | head -n1)

if [ -z "$IMAGE_FILE" ]; then
    log_error "No image file found in deploy directory"
    exit 1
fi

IMAGE_SIZE=$(stat -c%s "$IMAGE_FILE")
log_info "Image created: $(basename "$IMAGE_FILE")"
log_info "Image size: $(numfmt --to=iec-i --suffix=B $IMAGE_SIZE)"

# Generate checksums if requested
if [ "${GENERATE_CHECKSUMS}" = "true" ]; then
    log_info "Generating checksums..."
    cd "$DEPLOY_DIR"
    sha256sum "$(basename "$IMAGE_FILE")" > "$(basename "$IMAGE_FILE").sha256"
    log_info "✓ SHA256 checksum generated"
fi

################################################################################
# Summary
################################################################################

log_info "================================================================"
log_info "Build Complete!"
log_info "================================================================"
echo ""
echo "Build Information:"
echo "  - Build time: $(date -d@${BUILD_DURATION} -u +%H:%M:%S)"
echo "  - Image: $(basename "$IMAGE_FILE")"
echo "  - Size: $(numfmt --to=iec-i --suffix=B $IMAGE_SIZE)"
echo "  - Location: $DEPLOY_DIR"
echo ""
echo "Configuration:"
echo "  - Base: Raspberry Pi OS ${BASE_IMAGE} (${RPI_OS_RELEASE})"
echo "  - Architecture: ${ARCHITECTURE}"
echo "  - Username: ${RPI_USERNAME}"
echo "  - Hostname: ${HOSTNAME}"
echo "  - Auto-start: ${AUTOSTART_ENABLED}"
echo ""
echo "Next Steps:"
echo "  1. Test in QEMU:"
echo "     cd ../testing"
echo "     ./test-qemu.sh $IMAGE_FILE"
echo ""
echo "  2. Flash to SD card:"
echo "     sudo dd if=$IMAGE_FILE of=/dev/sdX bs=4M status=progress conv=fsync"
echo ""
log_info "Build completed successfully!"
