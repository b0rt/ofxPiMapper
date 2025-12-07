#!/bin/bash
################################################################################
# Wireless and Bluetooth Configuration Script
#
# This script configures wireless networking and Bluetooth for ofxPiMapper.
# It ensures NetworkManager is properly set up and enables Bluetooth services.
################################################################################

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

################################################################################
# NetworkManager Configuration
################################################################################

log_info "Configuring NetworkManager..."

# Ensure NetworkManager is enabled
if systemctl list-unit-files | grep -q NetworkManager.service; then
    log_info "NetworkManager is installed"
    systemctl enable NetworkManager.service
    log_info "✓ NetworkManager enabled"
else
    log_warn "NetworkManager not found, skipping..."
fi

# Configure NetworkManager to manage all network interfaces
if [ -f /etc/NetworkManager/NetworkManager.conf ]; then
    log_info "Configuring NetworkManager to manage all interfaces..."

    # Backup original config
    cp /etc/NetworkManager/NetworkManager.conf /etc/NetworkManager/NetworkManager.conf.bak

    # Set managed=true for ifupdown plugin
    cat > /etc/NetworkManager/conf.d/10-globally-managed-devices.conf <<EOF
[keyfile]
unmanaged-devices=none

[ifupdown]
managed=true
EOF

    log_info "✓ NetworkManager configuration updated"
fi

################################################################################
# WiFi Configuration
################################################################################

log_info "Configuring WiFi..."

# Set WiFi regulatory domain if specified
if [ -n "${WIFI_COUNTRY}" ]; then
    log_info "Setting WiFi country code to ${WIFI_COUNTRY}..."

    # Update /etc/default/crda if it exists
    if [ -f /etc/default/crda ]; then
        sed -i "s/^REGDOMAIN=.*/REGDOMAIN=${WIFI_COUNTRY}/" /etc/default/crda
    fi

    # Set using iw reg set (will be applied on boot)
    mkdir -p /etc/default
    echo "REGDOMAIN=${WIFI_COUNTRY}" > /etc/default/crda

    # Also configure wpa_supplicant
    if [ ! -f /etc/wpa_supplicant/wpa_supplicant.conf ]; then
        mkdir -p /etc/wpa_supplicant
        cat > /etc/wpa_supplicant/wpa_supplicant.conf <<EOF
country=${WIFI_COUNTRY}
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
EOF
        chmod 600 /etc/wpa_supplicant/wpa_supplicant.conf
    else
        # Update existing config
        if ! grep -q "^country=" /etc/wpa_supplicant/wpa_supplicant.conf; then
            sed -i "1i country=${WIFI_COUNTRY}" /etc/wpa_supplicant/wpa_supplicant.conf
        else
            sed -i "s/^country=.*/country=${WIFI_COUNTRY}/" /etc/wpa_supplicant/wpa_supplicant.conf
        fi
    fi

    log_info "✓ WiFi country set to ${WIFI_COUNTRY}"
fi

# Pre-configure WiFi network if credentials provided
if [ -n "${WIFI_SSID}" ] && [ -n "${WIFI_PASSWORD}" ]; then
    log_info "Pre-configuring WiFi network: ${WIFI_SSID}..."

    # Create NetworkManager connection file
    mkdir -p /etc/NetworkManager/system-connections

    cat > "/etc/NetworkManager/system-connections/${WIFI_SSID}" <<EOF
[connection]
id=${WIFI_SSID}
uuid=$(uuidgen)
type=wifi
autoconnect=true
autoconnect-priority=100

[wifi]
mode=infrastructure
ssid=${WIFI_SSID}

[wifi-security]
key-mgmt=wpa-psk
psk=${WIFI_PASSWORD}

[ipv4]
method=auto

[ipv6]
addr-gen-mode=stable-privacy
method=auto
EOF

    chmod 600 "/etc/NetworkManager/system-connections/${WIFI_SSID}"
    log_info "✓ WiFi network ${WIFI_SSID} configured"
else
    log_info "No WiFi credentials provided, skipping WiFi setup"
fi

################################################################################
# Bluetooth Configuration
################################################################################

log_info "Configuring Bluetooth..."

# Ensure Bluetooth service is enabled
if systemctl list-unit-files | grep -q bluetooth.service; then
    log_info "Bluetooth service found"
    systemctl enable bluetooth.service
    log_info "✓ Bluetooth service enabled"
else
    log_warn "Bluetooth service not found"
fi

# Configure Bluetooth for auto-power-on
if [ -f /etc/bluetooth/main.conf ]; then
    log_info "Configuring Bluetooth auto-power-on..."

    # Backup original config
    cp /etc/bluetooth/main.conf /etc/bluetooth/main.conf.bak

    # Enable auto-power-on
    if grep -q "^#AutoEnable=" /etc/bluetooth/main.conf; then
        sed -i 's/^#AutoEnable=.*/AutoEnable=true/' /etc/bluetooth/main.conf
    elif grep -q "^AutoEnable=" /etc/bluetooth/main.conf; then
        sed -i 's/^AutoEnable=.*/AutoEnable=true/' /etc/bluetooth/main.conf
    else
        echo "" >> /etc/bluetooth/main.conf
        echo "[Policy]" >> /etc/bluetooth/main.conf
        echo "AutoEnable=true" >> /etc/bluetooth/main.conf
    fi

    log_info "✓ Bluetooth auto-power-on enabled"
fi

################################################################################
# User Permissions
################################################################################

log_info "Configuring user permissions for networking..."

# Get the primary user (should be set via RPI_USERNAME env var)
PRIMARY_USER="${RPI_USERNAME:-mapper}"

if id "$PRIMARY_USER" &>/dev/null; then
    # Add user to netdev group for network management
    usermod -a -G netdev "$PRIMARY_USER"
    log_info "✓ User ${PRIMARY_USER} added to netdev group"

    # Add user to bluetooth group if it exists
    if getent group bluetooth > /dev/null 2>&1; then
        usermod -a -G bluetooth "$PRIMARY_USER"
        log_info "✓ User ${PRIMARY_USER} added to bluetooth group"
    fi
else
    log_warn "User ${PRIMARY_USER} not found, skipping group assignment"
fi

################################################################################
# Network Performance Tuning
################################################################################

log_info "Applying network performance tuning..."

# Disable WiFi power management for better performance
cat > /etc/NetworkManager/conf.d/wifi-powersave.conf <<EOF
[connection]
wifi.powersave = 2
EOF

log_info "✓ WiFi power management disabled for better performance"

################################################################################
# Create Helper Scripts
################################################################################

log_info "Creating network helper scripts..."

# Create WiFi connection helper script
cat > /usr/local/bin/connect-wifi <<'EOF'
#!/bin/bash
# Helper script to connect to WiFi network

if [ $# -lt 2 ]; then
    echo "Usage: connect-wifi <SSID> <PASSWORD>"
    exit 1
fi

SSID="$1"
PASSWORD="$2"

echo "Connecting to WiFi network: $SSID"
nmcli device wifi connect "$SSID" password "$PASSWORD"
EOF

chmod +x /usr/local/bin/connect-wifi

# Create WiFi list helper script
cat > /usr/local/bin/list-wifi <<'EOF'
#!/bin/bash
# Helper script to list available WiFi networks

echo "Scanning for WiFi networks..."
nmcli device wifi list
EOF

chmod +x /usr/local/bin/list-wifi

# Create Bluetooth helper script
cat > /usr/local/bin/bluetooth-status <<'EOF'
#!/bin/bash
# Helper script to show Bluetooth status

echo "Bluetooth Status:"
bluetoothctl show

echo ""
echo "Paired Devices:"
bluetoothctl devices
EOF

chmod +x /usr/local/bin/bluetooth-status

log_info "✓ Helper scripts created:"
log_info "  - connect-wifi <SSID> <PASSWORD>"
log_info "  - list-wifi"
log_info "  - bluetooth-status"

################################################################################
# Documentation
################################################################################

# Create quick reference guide
mkdir -p /home/${PRIMARY_USER}/Documents
cat > /home/${PRIMARY_USER}/Documents/NetworkingGuide.txt <<EOF
================================================================================
ofxPiMapper - Wireless and Bluetooth Quick Reference
================================================================================

WIFI MANAGEMENT
---------------

List available WiFi networks:
  list-wifi

Connect to WiFi network:
  connect-wifi "NetworkName" "password"

Check current connection:
  nmcli connection show --active

Disconnect from WiFi:
  nmcli connection down <connection-name>


BLUETOOTH MANAGEMENT
--------------------

Check Bluetooth status:
  bluetooth-status

Start Bluetooth interactive mode:
  bluetoothctl

In bluetoothctl:
  - scan on              # Start scanning for devices
  - devices              # List discovered devices
  - pair <MAC>           # Pair with device
  - connect <MAC>        # Connect to paired device
  - trust <MAC>          # Trust device for auto-connect
  - remove <MAC>         # Remove paired device


NETWORK TROUBLESHOOTING
-----------------------

Restart NetworkManager:
  sudo systemctl restart NetworkManager

View network logs:
  journalctl -u NetworkManager -f

Check WiFi country setting:
  iw reg get

Set WiFi country (if needed):
  sudo iw reg set US

Check interface status:
  ip link show


CONFIGURATION FILES
-------------------

NetworkManager config:     /etc/NetworkManager/NetworkManager.conf
WiFi connections:          /etc/NetworkManager/system-connections/
wpa_supplicant config:     /etc/wpa_supplicant/wpa_supplicant.conf
Bluetooth config:          /etc/bluetooth/main.conf


For more help, visit: https://github.com/b0rt/ofxPiMapper
================================================================================
EOF

chown ${PRIMARY_USER}:${PRIMARY_USER} /home/${PRIMARY_USER}/Documents/NetworkingGuide.txt

log_info "✓ Networking guide created at ~/Documents/NetworkingGuide.txt"

################################################################################
# Summary
################################################################################

echo ""
log_info "================================================================"
log_info "Wireless and Bluetooth Configuration Complete!"
log_info "================================================================"
echo ""
echo "Configured:"
echo "  ✓ NetworkManager (manages WiFi and Ethernet)"
echo "  ✓ WiFi ${WIFI_COUNTRY:+(country: $WIFI_COUNTRY)}"
echo "  ${WIFI_SSID:+✓ Pre-configured network: $WIFI_SSID}"
echo "  ✓ Bluetooth (auto-power-on enabled)"
echo "  ✓ User permissions for ${PRIMARY_USER}"
echo "  ✓ Helper scripts installed"
echo ""
echo "Quick commands:"
echo "  - list-wifi          # Show available WiFi networks"
echo "  - connect-wifi       # Connect to WiFi"
echo "  - bluetooth-status   # Show Bluetooth status"
echo ""
log_info "Wireless and Bluetooth setup completed successfully!"
