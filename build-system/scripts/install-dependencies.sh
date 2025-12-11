#!/bin/bash
################################################################################
# Install System Dependencies for ofxPiMapper
#
# This script installs all required system packages and libraries needed for
# openFrameworks and ofxPiMapper on Raspberry Pi.
#
# Usage: sudo ./install-dependencies.sh
################################################################################

set -e  # Exit on error
set -u  # Exit on undefined variable

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    log_error "Please run as root (use sudo)"
    exit 1
fi

log_info "Starting dependency installation for ofxPiMapper"

################################################################################
# Update System
################################################################################

log_info "Updating package lists..."
apt-get update -y

log_info "Upgrading existing packages..."
apt-get upgrade -y

################################################################################
# Install Build Essentials
################################################################################

log_info "Installing build essentials..."
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

log_info "Installing OpenGL ES and graphics libraries..."
apt-get install -y \
    libgles2-mesa-dev \
    libglu1-mesa-dev \
    libglew-dev \
    libglfw3-dev \
    libegl1-mesa-dev \
    mesa-utils \
    libdrm-dev \
    libgbm-dev

################################################################################
# Install GStreamer (Required for video playback)
################################################################################

log_info "Installing GStreamer and plugins..."
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

# Raspberry Pi specific GStreamer components
if [ -f /proc/device-tree/model ] && grep -q "Raspberry Pi" /proc/device-tree/model; then
    log_info "Installing Raspberry Pi specific GStreamer components..."
    apt-get install -y \
        gstreamer1.0-omx-rpi \
        gstreamer1.0-omx-rpi-config \
        || log_warn "OMX packages not available on this OS version"
fi

################################################################################
# Install Audio Libraries
################################################################################

log_info "Installing audio libraries..."
apt-get install -y \
    libasound2-dev \
    libpulse-dev \
    alsa-utils \
    pulseaudio \
    libmpg123-dev \
    libsndfile1-dev \
    libfreeimage-dev

# Configure audio for better performance
if command -v alsactl &> /dev/null; then
    log_info "Configuring ALSA..."
    alsactl init || true
fi

################################################################################
# Install Additional Libraries
################################################################################

log_info "Installing additional required libraries..."
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
    libx264-dev \
    liburiparser-dev

################################################################################
# Install Utilities
################################################################################

log_info "Installing utilities..."
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
# Install Raspberry Pi Specific Packages
################################################################################

if [ -f /proc/device-tree/model ] && grep -q "Raspberry Pi" /proc/device-tree/model; then
    log_info "Installing Raspberry Pi specific packages..."

    # Raspberry Pi utilities
    apt-get install -y \
        libraspberrypi-dev \
        libraspberrypi-bin \
        raspberrypi-kernel-headers \
        || log_warn "Some Raspberry Pi packages not available"

    # Camera support
    if [ "${INSTALL_CAMERA_SUPPORT:-true}" = "true" ]; then
        log_info "Installing camera support..."
        apt-get install -y \
            libcamera-dev \
            libcamera-apps \
            || log_warn "Camera packages not available"
    fi
fi

################################################################################
# Install Python (for some oF scripts)
################################################################################

log_info "Installing Python..."
apt-get install -y \
    python3 \
    python3-pip \
    python3-dev

################################################################################
# Configure GPU Memory
################################################################################

if [ -f /boot/config.txt ]; then
    GPU_MEM_SETTING="${GPU_MEM:-256}"
    log_info "Configuring GPU memory to ${GPU_MEM_SETTING}MB..."

    # Remove existing gpu_mem settings
    sed -i '/^gpu_mem=/d' /boot/config.txt

    # Add new gpu_mem setting
    echo "gpu_mem=${GPU_MEM_SETTING}" >> /boot/config.txt
elif [ -f /boot/firmware/config.txt ]; then
    GPU_MEM_SETTING="${GPU_MEM:-256}"
    log_info "Configuring GPU memory to ${GPU_MEM_SETTING}MB..."

    # Remove existing gpu_mem settings
    sed -i '/^gpu_mem=/d' /boot/firmware/config.txt

    # Add new gpu_mem setting
    echo "gpu_mem=${GPU_MEM_SETTING}" >> /boot/firmware/config.txt
fi

################################################################################
# Configure HDMI
################################################################################

CONFIG_FILE="/boot/config.txt"
if [ ! -f "$CONFIG_FILE" ] && [ -f "/boot/firmware/config.txt" ]; then
    CONFIG_FILE="/boot/firmware/config.txt"
fi

if [ -f "$CONFIG_FILE" ]; then
    log_info "Configuring HDMI settings..."

    # Force HDMI hotplug
    if [ "${HDMI_FORCE_HOTPLUG:-1}" = "1" ]; then
        sed -i '/^#\?hdmi_force_hotplug=/d' "$CONFIG_FILE"
        echo "hdmi_force_hotplug=1" >> "$CONFIG_FILE"
    fi

    # HDMI drive mode (2 = HDMI with audio)
    if [ "${HDMI_DRIVE:-2}" != "" ]; then
        sed -i '/^#\?hdmi_drive=/d' "$CONFIG_FILE"
        echo "hdmi_drive=${HDMI_DRIVE}" >> "$CONFIG_FILE"
    fi
fi

################################################################################
# Performance Tuning
################################################################################

log_info "Applying performance tuning..."

# Disable swap if requested
if [ "${DISABLE_SWAP:-false}" = "true" ]; then
    log_info "Disabling swap..."
    systemctl disable dphys-swapfile || true
    systemctl stop dphys-swapfile || true
fi

# Set CPU governor
if [ "${CPU_GOVERNOR:-}" != "" ]; then
    log_info "Setting CPU governor to ${CPU_GOVERNOR}..."
    apt-get install -y cpufrequtils

    cat > /etc/default/cpufrequtils <<EOF
GOVERNOR="${CPU_GOVERNOR}"
EOF

    systemctl restart cpufrequtils || true
fi

# Overclock settings (use with caution)
if [ "${ENABLE_OVERCLOCK:-false}" = "true" ] && [ -f "$CONFIG_FILE" ]; then
    log_warn "Enabling overclock settings (may void warranty)..."

    sed -i '/^#\?arm_freq=/d' "$CONFIG_FILE"
    sed -i '/^#\?gpu_freq=/d' "$CONFIG_FILE"
    sed -i '/^#\?over_voltage=/d' "$CONFIG_FILE"

    echo "arm_freq=${OVERCLOCK_ARM_FREQ:-2000}" >> "$CONFIG_FILE"
    echo "gpu_freq=${OVERCLOCK_GPU_FREQ:-750}" >> "$CONFIG_FILE"
    echo "over_voltage=6" >> "$CONFIG_FILE"
fi

################################################################################
# Clean up
################################################################################

log_info "Cleaning up..."
apt-get autoremove -y
apt-get autoclean -y

################################################################################
# Create symbolic links for compatibility
################################################################################

log_info "Creating compatibility symbolic links..."

# Link libGLESv2 if needed
if [ ! -f /usr/lib/arm-linux-gnueabihf/libGLESv2.so ] && [ -f /usr/lib/arm-linux-gnueabihf/libGLESv2.so.2 ]; then
    ln -sf /usr/lib/arm-linux-gnueabihf/libGLESv2.so.2 /usr/lib/arm-linux-gnueabihf/libGLESv2.so
fi

################################################################################
# Verify Installation
################################################################################

log_info "Verifying installation..."

FAILED=0

# Check for critical packages
for pkg in git cmake gcc g++ make pkg-config; do
    if ! command -v $pkg &> /dev/null; then
        log_error "Required package not found: $pkg"
        FAILED=1
    fi
done

# Check for critical libraries
for lib in libgles2 libglfw3 libasound2; do
    if ! ldconfig -p | grep -q $lib; then
        log_warn "Library may be missing: $lib"
    fi
done

if [ $FAILED -eq 0 ]; then
    log_info "Dependency installation completed successfully!"
    log_info "System is ready for openFrameworks and ofxPiMapper installation."
else
    log_error "Some dependencies failed to install. Please review the log."
    exit 1
fi

# Print system information
log_info "System Information:"
echo "  - Kernel: $(uname -r)"
echo "  - Architecture: $(uname -m)"
if [ -f /proc/device-tree/model ]; then
    echo "  - Model: $(cat /proc/device-tree/model)"
fi
echo "  - GCC Version: $(gcc --version | head -n1)"
echo "  - CMake Version: $(cmake --version | head -n1)"

log_info "Installation complete. A reboot is recommended to apply all changes."
