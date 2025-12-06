#!/bin/bash
################################################################################
# Configure Auto-start for ofxPiMapper
#
# Configures ofxPiMapper to automatically start on boot in fullscreen mode.
#
# Usage: ./configure-autostart.sh [target_user] [project_name]
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

# Configuration
TARGET_USER="${1:-${RPI_USERNAME:-$(whoami)}}"
PROJECT_NAME="${2:-${AUTOSTART_PROJECT:-example_simpler}}"
OF_ROOT="${OF_ROOT:-/home/${TARGET_USER}/openFrameworks}"
AUTOSTART_ENABLED="${AUTOSTART_ENABLED:-false}"
AUTOSTART_FULLSCREEN="${AUTOSTART_FULLSCREEN:-true}"
AUTOSTART_DELAY="${AUTOSTART_DELAY:-10}"
AUTOSTART_RESTART_ON_CRASH="${AUTOSTART_RESTART_ON_CRASH:-true}"

if [ "$AUTOSTART_ENABLED" != "true" ]; then
    log_info "Auto-start disabled in configuration"
    exit 0
fi

log_info "Configuring auto-start for ${PROJECT_NAME}"
log_info "User: ${TARGET_USER}"
log_info "Delay: ${AUTOSTART_DELAY} seconds"
log_info "Fullscreen: ${AUTOSTART_FULLSCREEN}"

# Verify user exists
if ! id "$TARGET_USER" &>/dev/null; then
    log_error "User ${TARGET_USER} does not exist"
    exit 1
fi

USER_HOME="/home/${TARGET_USER}"
PROJECT_PATH="${OF_ROOT}/addons/ofxPiMapper/${PROJECT_NAME}"
BINARY_PATH="${PROJECT_PATH}/bin/${PROJECT_NAME}"

# Verify project exists
if [ ! -d "$PROJECT_PATH" ]; then
    log_error "Project not found: ${PROJECT_PATH}"
    exit 1
fi

if [ ! -f "$BINARY_PATH" ]; then
    log_error "Binary not found: ${BINARY_PATH}"
    log_error "Please compile the project first"
    exit 1
fi

################################################################################
# Method 1: XDG Autostart (Desktop Environment)
################################################################################

log_info "Creating XDG autostart entry..."

AUTOSTART_DIR="${USER_HOME}/.config/autostart"
mkdir -p "$AUTOSTART_DIR"

FULLSCREEN_FLAG=""
if [ "$AUTOSTART_FULLSCREEN" = "true" ]; then
    FULLSCREEN_FLAG="-f"
fi

cat > "${AUTOSTART_DIR}/ofxpimapper.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=ofxPiMapper
Comment=Projection mapping application
Exec=bash -c 'sleep ${AUTOSTART_DELAY} && cd ${PROJECT_PATH} && DISPLAY=:0 ${BINARY_PATH} ${FULLSCREEN_FLAG}'
Terminal=false
Hidden=false
X-GNOME-Autostart-enabled=true
StartupNotify=false
EOF

chown -R "${TARGET_USER}:${TARGET_USER}" "$AUTOSTART_DIR"
chmod +x "${AUTOSTART_DIR}/ofxpimapper.desktop"

log_info "✓ XDG autostart entry created"

################################################################################
# Method 2: LXDE Autostart
################################################################################

log_info "Creating LXDE autostart entry..."

LXSESSION_DIR="${USER_HOME}/.config/lxsession/LXDE-pi"
mkdir -p "$LXSESSION_DIR"

# Append to autostart if it exists, create if it doesn't
if [ -f "${LXSESSION_DIR}/autostart" ]; then
    # Remove any existing ofxPiMapper autostart lines
    sed -i '/ofxPiMapper/d' "${LXSESSION_DIR}/autostart"
else
    # Create new autostart file with defaults
    cat > "${LXSESSION_DIR}/autostart" <<'EOF'
@lxpanel --profile LXDE-pi
@pcmanfm --desktop --profile LXDE-pi
@xscreensaver -no-splash
@xset s off
@xset -dpms
@xset s noblank
EOF
fi

# Add ofxPiMapper autostart command
cat >> "${LXSESSION_DIR}/autostart" <<EOF

# ofxPiMapper auto-start
@bash -c 'sleep ${AUTOSTART_DELAY} && cd ${PROJECT_PATH} && ${BINARY_PATH} ${FULLSCREEN_FLAG}'
EOF

chown -R "${TARGET_USER}:${TARGET_USER}" "$LXSESSION_DIR"

log_info "✓ LXDE autostart entry created"

################################################################################
# Method 3: Systemd Service (Most Reliable)
################################################################################

log_info "Creating systemd service..."

SERVICE_NAME="ofxpimapper"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=ofxPiMapper Projection Mapping
After=graphical.target network.target
Wants=graphical.target

[Service]
Type=simple
User=${TARGET_USER}
Group=${TARGET_USER}
WorkingDirectory=${PROJECT_PATH}
Environment="DISPLAY=:0"
Environment="XAUTHORITY=${USER_HOME}/.Xauthority"
Environment="OF_ROOT=${OF_ROOT}"
ExecStartPre=/bin/sleep ${AUTOSTART_DELAY}
ExecStart=${BINARY_PATH} ${FULLSCREEN_FLAG}
Restart=$([ "$AUTOSTART_RESTART_ON_CRASH" = "true" ] && echo "always" || echo "no")
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=graphical.target
EOF

# Reload systemd
systemctl daemon-reload

# Enable the service (but don't start it now)
systemctl enable "${SERVICE_NAME}.service"

log_info "✓ Systemd service created and enabled"

################################################################################
# Create Management Scripts
################################################################################

log_info "Creating management scripts..."

# Start script
cat > "${USER_HOME}/start-ofxpimapper.sh" <<EOFSCRIPT
#!/bin/bash
# Manually start ofxPiMapper

cd ${PROJECT_PATH}
${BINARY_PATH} ${FULLSCREEN_FLAG}
EOFSCRIPT

chmod +x "${USER_HOME}/start-ofxpimapper.sh"

# Stop script
cat > "${USER_HOME}/stop-ofxpimapper.sh" <<'EOFSCRIPT'
#!/bin/bash
# Stop ofxPiMapper

echo "Stopping ofxPiMapper..."

# Stop systemd service
sudo systemctl stop ofxpimapper.service 2>/dev/null || true

# Kill any running instances
pkill -f "ofxpimapper/.*example_" || true

echo "ofxPiMapper stopped"
EOFSCRIPT

chmod +x "${USER_HOME}/stop-ofxpimapper.sh"

# Disable auto-start script
cat > "${USER_HOME}/disable-autostart.sh" <<'EOFSCRIPT'
#!/bin/bash
# Disable ofxPiMapper auto-start

echo "Disabling ofxPiMapper auto-start..."

# Disable systemd service
sudo systemctl disable ofxpimapper.service 2>/dev/null || true
sudo systemctl stop ofxpimapper.service 2>/dev/null || true

# Remove XDG autostart
rm -f ~/.config/autostart/ofxpimapper.desktop

# Remove from LXDE autostart
if [ -f ~/.config/lxsession/LXDE-pi/autostart ]; then
    sed -i '/ofxPiMapper/d' ~/.config/lxsession/LXDE-pi/autostart
fi

echo "Auto-start disabled"
echo "Run ./start-ofxpimapper.sh to start manually"
EOFSCRIPT

chmod +x "${USER_HOME}/disable-autostart.sh"

# Enable auto-start script
cat > "${USER_HOME}/enable-autostart.sh" <<EOFSCRIPT
#!/bin/bash
# Enable ofxPiMapper auto-start

echo "Enabling ofxPiMapper auto-start..."

sudo systemctl enable ofxpimapper.service
sudo systemctl start ofxpimapper.service

echo "Auto-start enabled"
echo "ofxPiMapper will start automatically on next boot"
EOFSCRIPT

chmod +x "${USER_HOME}/enable-autostart.sh"

# Status script
cat > "${USER_HOME}/status-ofxpimapper.sh" <<'EOFSCRIPT'
#!/bin/bash
# Check ofxPiMapper status

echo "ofxPiMapper Status"
echo "=================="
echo ""

# Check systemd service
echo "Systemd Service:"
sudo systemctl status ofxpimapper.service --no-pager | grep -E "Active:|Loaded:" || echo "  Not configured"
echo ""

# Check for running processes
echo "Running Processes:"
pgrep -f "ofxpimapper/.*example_" && ps aux | grep "[o]fxpimapper" || echo "  No processes running"
echo ""

# Check autostart configurations
echo "Autostart Configurations:"
if [ -f ~/.config/autostart/ofxpimapper.desktop ]; then
    echo "  ✓ XDG autostart enabled"
else
    echo "  ✗ XDG autostart disabled"
fi

if [ -f ~/.config/lxsession/LXDE-pi/autostart ] && grep -q "ofxPiMapper" ~/.config/lxsession/LXDE-pi/autostart; then
    echo "  ✓ LXDE autostart enabled"
else
    echo "  ✗ LXDE autostart disabled"
fi

if systemctl is-enabled ofxpimapper.service &>/dev/null; then
    echo "  ✓ Systemd service enabled"
else
    echo "  ✗ Systemd service disabled"
fi
EOFSCRIPT

chmod +x "${USER_HOME}/status-ofxpimapper.sh"

# Set ownership
chown "${TARGET_USER}:${TARGET_USER}" "${USER_HOME}/"*.sh

log_info "✓ Management scripts created"

################################################################################
# Create Watchdog Script (Optional)
################################################################################

if [ "$AUTOSTART_RESTART_ON_CRASH" = "true" ]; then
    log_info "Creating watchdog script..."

    cat > "${USER_HOME}/ofxpimapper-watchdog.sh" <<EOFSCRIPT
#!/bin/bash
# Watchdog script to restart ofxPiMapper if it crashes

PROJECT_PATH="${PROJECT_PATH}"
BINARY_PATH="${BINARY_PATH}"
FULLSCREEN_FLAG="${FULLSCREEN_FLAG}"
CHECK_INTERVAL=30  # seconds

while true; do
    if ! pgrep -f "${BINARY_PATH}" > /dev/null; then
        echo "\$(date): ofxPiMapper not running, restarting..."
        cd "\$PROJECT_PATH"
        DISPLAY=:0 "\$BINARY_PATH" \$FULLSCREEN_FLAG &
    fi
    sleep \$CHECK_INTERVAL
done
EOFSCRIPT

    chmod +x "${USER_HOME}/ofxpimapper-watchdog.sh"
    chown "${TARGET_USER}:${TARGET_USER}" "${USER_HOME}/ofxpimapper-watchdog.sh"

    log_info "✓ Watchdog script created"
fi

################################################################################
# Summary
################################################################################

log_info "================================================================"
log_info "Auto-start Configuration Complete"
log_info "================================================================"
echo ""
echo "Configuration:"
echo "  - Project: ${PROJECT_NAME}"
echo "  - Binary: ${BINARY_PATH}"
echo "  - Fullscreen: ${AUTOSTART_FULLSCREEN}"
echo "  - Delay: ${AUTOSTART_DELAY} seconds"
echo "  - Restart on crash: ${AUTOSTART_RESTART_ON_CRASH}"
echo ""
echo "Auto-start methods configured:"
echo "  ✓ XDG autostart (.config/autostart)"
echo "  ✓ LXDE autostart"
echo "  ✓ Systemd service"
echo ""
echo "Management scripts created in ${USER_HOME}:"
echo "  - start-ofxpimapper.sh       Start manually"
echo "  - stop-ofxpimapper.sh        Stop running instance"
echo "  - status-ofxpimapper.sh      Check status"
echo "  - enable-autostart.sh        Enable auto-start"
echo "  - disable-autostart.sh       Disable auto-start"
echo ""
echo "Current status:"
systemctl is-enabled ofxpimapper.service &>/dev/null && echo "  ✓ Auto-start enabled" || echo "  ✓ Auto-start will be active after reboot"
echo ""
log_info "ofxPiMapper will start automatically after the next reboot"
