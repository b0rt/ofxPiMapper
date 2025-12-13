#!/bin/bash
################################################################################
# Configure X11 Display Server
#
# Forces X11 instead of Wayland and configures display settings for optimal
# projection mapping performance.
#
# Usage: sudo ./configure-x11.sh [target_user]
################################################################################

set -e  # Exit on error

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check root
if [ "$EUID" -ne 0 ]; then
    log_error "Please run as root (use sudo)"
    exit 1
fi

TARGET_USER="${1:-${RPI_USERNAME:-$(whoami)}}"
FORCE_X11="${FORCE_X11:-true}"

log_info "Configuring X11 display server for ${TARGET_USER}"

################################################################################
# Force X11 (Disable Wayland)
################################################################################

if [ "$FORCE_X11" = "true" ]; then
    log_info "Forcing X11 display server (disabling Wayland)..."

    # Configure GDM (GNOME Display Manager)
    if [ -f /etc/gdm3/custom.conf ]; then
        log_info "Configuring GDM3 to use X11..."
        sed -i 's/#WaylandEnable=false/WaylandEnable=false/' /etc/gdm3/custom.conf
        sed -i 's/WaylandEnable=true/WaylandEnable=false/' /etc/gdm3/custom.conf
    fi

    # Configure for desktop environments
    USER_HOME=$(getent passwd "${TARGET_USER}" | cut -d: -f6)

    # LXDE/Openbox configuration (Raspberry Pi OS default)
    if command -v openbox &> /dev/null; then
        log_info "Detected LXDE/Openbox environment"

        # Create Openbox autostart
        OPENBOX_DIR="${USER_HOME}/.config/openbox"
        mkdir -p "$OPENBOX_DIR"

        cat > "${OPENBOX_DIR}/environment" <<EOF
# Force X11 display
export GDK_BACKEND=x11
export QT_QPA_PLATFORM=xcb
export DISPLAY=:0
EOF

        chown -R "${TARGET_USER}:${TARGET_USER}" "$OPENBOX_DIR"
    fi

    # Set environment variables for X11
    cat > /etc/profile.d/force-x11.sh <<EOF
# Force X11 display server
export GDK_BACKEND=x11
export QT_QPA_PLATFORM=xcb
export XDG_SESSION_TYPE=x11
EOF

    chmod +x /etc/profile.d/force-x11.sh
fi

################################################################################
# Configure X11 Display Settings
################################################################################

log_info "Configuring X11 display settings..."

USER_HOME=$(getent passwd "${TARGET_USER}" | cut -d: -f6)
XORG_CONF_DIR="/etc/X11/xorg.conf.d"
mkdir -p "$XORG_CONF_DIR"

# Screen resolution (if specified)
if [ -n "${SCREEN_WIDTH:-}" ] && [ -n "${SCREEN_HEIGHT:-}" ]; then
    log_info "Setting screen resolution to ${SCREEN_WIDTH}x${SCREEN_HEIGHT}"

    cat > "${XORG_CONF_DIR}/99-screen-resolution.conf" <<EOF
Section "Monitor"
    Identifier "HDMI-1"
    Modeline "$(cvt ${SCREEN_WIDTH} ${SCREEN_HEIGHT} 60 | grep Modeline | sed 's/Modeline //')"
    Option "PreferredMode" "${SCREEN_WIDTH}x${SCREEN_HEIGHT}"
EndSection

Section "Screen"
    Identifier "Screen0"
    Monitor "HDMI-1"
    DefaultDepth 24
    SubSection "Display"
        Depth 24
        Modes "${SCREEN_WIDTH}x${SCREEN_HEIGHT}"
    EndSubSection
EndSection
EOF
fi

# Disable screen blanking and power management
cat > "${XORG_CONF_DIR}/99-no-blanking.conf" <<EOF
Section "ServerFlags"
    Option "BlankTime" "0"
    Option "StandbyTime" "0"
    Option "SuspendTime" "0"
    Option "OffTime" "0"
EndSection

Section "ServerLayout"
    Identifier "ServerLayout0"
    Option "BlankTime" "0"
EndSection
EOF

log_info "✓ Screen blanking disabled"

################################################################################
# Configure OpenGL Settings
################################################################################

log_info "Configuring OpenGL settings..."

# Create environment.d directory if it doesn't exist
mkdir -p /etc/environment.d

# Force OpenGL ES 2.0 for better compatibility
cat > /etc/environment.d/opengl.conf <<EOF
# Force OpenGL ES 2.0
MESA_GLES_VERSION_OVERRIDE=2.0
MESA_GL_VERSION_OVERRIDE=2.1
EOF

################################################################################
# Disable Compositor (for better performance)
################################################################################

log_info "Disabling compositor for better graphics performance..."

# For LXDE
if [ -f "${USER_HOME}/.config/lxsession/LXDE-pi/desktop.conf" ]; then
    mkdir -p "${USER_HOME}/.config/lxsession/LXDE-pi"
    sed -i 's/window_manager=.*/window_manager=openbox-lxde/' "${USER_HOME}/.config/lxsession/LXDE-pi/desktop.conf"
    chown -R "${TARGET_USER}:${TARGET_USER}" "${USER_HOME}/.config/lxsession"
fi

################################################################################
# Create xinitrc for Manual X11 Start
################################################################################

log_info "Creating .xinitrc..."

# Ensure user home directory exists
mkdir -p "${USER_HOME}"

cat > "${USER_HOME}/.xinitrc" <<EOF
#!/bin/sh
# .xinitrc for ofxPiMapper

# Disable screen blanking
xset s off
xset -dpms
xset s noblank

# Disable screensaver
if command -v xscreensaver-command &> /dev/null; then
    xscreensaver-command -exit
fi

# Set keyboard repeat rate (optional)
xset r rate 200 30

# Start window manager
exec openbox-session
EOF

chmod +x "${USER_HOME}/.xinitrc"
chown "${TARGET_USER}:${TARGET_USER}" "${USER_HOME}/.xinitrc"

################################################################################
# Configure DRM/KMS Settings for Better Graphics
################################################################################

log_info "Configuring DRM/KMS for better graphics performance..."

CONFIG_FILE="/boot/config.txt"
if [ ! -f "$CONFIG_FILE" ] && [ -f "/boot/firmware/config.txt" ]; then
    CONFIG_FILE="/boot/firmware/config.txt"
fi

if [ -f "$CONFIG_FILE" ]; then
    # Enable KMS (Kernel Mode Setting)
    if ! grep -q "^dtoverlay=vc4-kms-v3d" "$CONFIG_FILE"; then
        log_info "Enabling KMS driver..."
        echo "" >> "$CONFIG_FILE"
        echo "# Enable KMS graphics driver" >> "$CONFIG_FILE"
        echo "dtoverlay=vc4-kms-v3d" >> "$CONFIG_FILE"
    fi

    # Disable overscan for full screen use
    sed -i 's/^#\?disable_overscan=.*/disable_overscan=1/' "$CONFIG_FILE"
    if ! grep -q "^disable_overscan=" "$CONFIG_FILE"; then
        echo "disable_overscan=1" >> "$CONFIG_FILE"
    fi
fi

################################################################################
# Create X11 Test Script
################################################################################

log_info "Creating X11 test script..."

cat > "${USER_HOME}/test-x11.sh" <<'EOFSCRIPT'
#!/bin/bash
# Test X11 configuration

echo "Testing X11 Display Configuration"
echo "=================================="
echo ""

# Check display
if [ -z "$DISPLAY" ]; then
    echo "Warning: DISPLAY not set"
    export DISPLAY=:0
fi

echo "DISPLAY: $DISPLAY"
echo ""

# Check X server
if command -v xdpyinfo &> /dev/null; then
    echo "X Server Information:"
    xdpyinfo | grep -E "name of display|version number|screen #|dimensions|resolution"
else
    echo "xdpyinfo not available"
fi
echo ""

# Check OpenGL
if command -v glxinfo &> /dev/null; then
    echo "OpenGL Information:"
    glxinfo | grep -E "OpenGL version|OpenGL renderer|OpenGL vendor"
elif command -v es2_info &> /dev/null; then
    echo "OpenGL ES Information:"
    es2_info | grep -E "GL_VERSION|GL_RENDERER|GL_VENDOR"
else
    echo "OpenGL test tools not available"
fi
echo ""

# Check session type
echo "Session Type: ${XDG_SESSION_TYPE:-unknown}"
echo ""

# Test simple X application
if command -v xeyes &> /dev/null; then
    echo "Starting xeyes as test..."
    echo "If you see eyes following your cursor, X11 is working!"
    echo "Press Ctrl+C to exit"
    xeyes
else
    echo "xeyes not available for testing"
fi
EOFSCRIPT

chmod +x "${USER_HOME}/test-x11.sh"
chown "${TARGET_USER}:${TARGET_USER}" "${USER_HOME}/test-x11.sh"

################################################################################
# Summary
################################################################################

log_info "================================================================"
log_info "X11 Configuration Complete"
log_info "================================================================"
echo ""
echo "Configuration applied:"
echo "  - X11 display server: ${FORCE_X11}"
echo "  - Screen blanking: disabled"
echo "  - Compositor: disabled"
echo "  - KMS driver: enabled"
echo ""
echo "Test X11 configuration:"
echo "  ${USER_HOME}/test-x11.sh"
echo ""
log_info "A reboot is recommended to apply all changes"
