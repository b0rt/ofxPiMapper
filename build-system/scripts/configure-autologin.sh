#!/bin/bash
################################################################################
# Configure Auto-login to Desktop
#
# Configures automatic login to the desktop environment for the specified user.
#
# Usage: sudo ./configure-autologin.sh [target_user]
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
ENABLE_AUTOLOGIN="${ENABLE_AUTOLOGIN:-true}"

if [ "$ENABLE_AUTOLOGIN" != "true" ]; then
    log_info "Auto-login disabled in configuration"
    exit 0
fi

log_info "Configuring auto-login for ${TARGET_USER}"

# Verify user exists
if ! id "$TARGET_USER" &>/dev/null; then
    log_error "User ${TARGET_USER} does not exist"
    exit 1
fi

################################################################################
# Configure LightDM (Common on Raspberry Pi OS Desktop)
################################################################################

if [ -f /etc/lightdm/lightdm.conf ]; then
    log_info "Configuring LightDM for auto-login..."

    # Backup original config
    cp /etc/lightdm/lightdm.conf /etc/lightdm/lightdm.conf.backup

    # Configure auto-login
    sed -i "s/^#autologin-user=.*/autologin-user=${TARGET_USER}/" /etc/lightdm/lightdm.conf
    sed -i "s/^autologin-user=.*/autologin-user=${TARGET_USER}/" /etc/lightdm/lightdm.conf

    # Ensure autologin-user is uncommented
    if ! grep -q "^autologin-user=" /etc/lightdm/lightdm.conf; then
        echo "autologin-user=${TARGET_USER}" >> /etc/lightdm/lightdm.conf
    fi

    # Disable autologin timeout
    sed -i "s/^#autologin-user-timeout=.*/autologin-user-timeout=0/" /etc/lightdm/lightdm.conf
    sed -i "s/^autologin-user-timeout=.*/autologin-user-timeout=0/" /etc/lightdm/lightdm.conf

    # Add user to autologin group
    groupadd -f autologin
    usermod -a -G autologin "$TARGET_USER"

    log_info "✓ LightDM configured"
fi

################################################################################
# Configure GDM3 (GNOME Display Manager)
################################################################################

if [ -f /etc/gdm3/custom.conf ]; then
    log_info "Configuring GDM3 for auto-login..."

    # Backup original config
    cp /etc/gdm3/custom.conf /etc/gdm3/custom.conf.backup

    # Enable auto-login
    sed -i "s/^#AutomaticLoginEnable.*/AutomaticLoginEnable = true/" /etc/gdm3/custom.conf
    sed -i "s/^#AutomaticLogin.*/AutomaticLogin = ${TARGET_USER}/" /etc/gdm3/custom.conf

    # Ensure settings are uncommented
    if ! grep -q "^AutomaticLoginEnable" /etc/gdm3/custom.conf; then
        sed -i "/\[daemon\]/a AutomaticLoginEnable = true\nAutomaticLogin = ${TARGET_USER}" /etc/gdm3/custom.conf
    fi

    log_info "✓ GDM3 configured"
fi

################################################################################
# Configure Getty (Console Auto-login)
################################################################################

log_info "Configuring console auto-login (getty)..."

# Create override directory for getty
GETTY_OVERRIDE_DIR="/etc/systemd/system/getty@tty1.service.d"
mkdir -p "$GETTY_OVERRIDE_DIR"

# Configure auto-login
cat > "${GETTY_OVERRIDE_DIR}/autologin.conf" <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin ${TARGET_USER} --noclear %I \$TERM
EOF

log_info "✓ Console auto-login configured"

################################################################################
# Configure systemd for Graphical Target
################################################################################

log_info "Setting default boot target to graphical..."

systemctl set-default graphical.target

################################################################################
# Disable Password for Sudo (Optional, for convenience)
################################################################################

if [ "${DISABLE_SUDO_PASSWORD:-false}" = "true" ]; then
    log_warn "Disabling sudo password for ${TARGET_USER} (not recommended for production)"

    SUDOERS_FILE="/etc/sudoers.d/010_${TARGET_USER}-nopasswd"
    echo "${TARGET_USER} ALL=(ALL) NOPASSWD: ALL" > "$SUDOERS_FILE"
    chmod 0440 "$SUDOERS_FILE"

    log_info "✓ Sudo password disabled for ${TARGET_USER}"
fi

################################################################################
# Create User Session Configuration
################################################################################

USER_HOME="/home/${TARGET_USER}"

# Ensure user directories exist
mkdir -p "${USER_HOME}/.config"
chown -R "${TARGET_USER}:${TARGET_USER}" "${USER_HOME}/.config"

# Disable screen lock
mkdir -p "${USER_HOME}/.config/lxsession/LXDE-pi"
cat > "${USER_HOME}/.config/lxsession/LXDE-pi/autostart" <<EOF
@lxpanel --profile LXDE-pi
@pcmanfm --desktop --profile LXDE-pi
@xscreensaver -no-splash

# Disable screen blanking
@xset s off
@xset -dpms
@xset s noblank
EOF

chown -R "${TARGET_USER}:${TARGET_USER}" "${USER_HOME}/.config/lxsession"

################################################################################
# Summary
################################################################################

log_info "================================================================"
log_info "Auto-login Configuration Complete"
log_info "================================================================"
echo ""
echo "Configuration applied:"
echo "  - Auto-login user: ${TARGET_USER}"
echo "  - Default target: graphical"
echo "  - Console auto-login: enabled"
echo ""

if [ -f /etc/lightdm/lightdm.conf ]; then
    echo "  - LightDM: configured"
fi

if [ -f /etc/gdm3/custom.conf ]; then
    echo "  - GDM3: configured"
fi

echo ""
log_info "Changes will take effect after reboot"
