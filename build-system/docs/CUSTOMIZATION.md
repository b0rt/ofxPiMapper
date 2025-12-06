# Build System Customization Guide

This guide explains how to customize the ofxPiMapper build system to create images tailored to your specific needs.

## Table of Contents

1. [Basic Customization](#basic-customization)
2. [Advanced Configuration](#advanced-configuration)
3. [Adding Custom Software](#adding-custom-software)
4. [Custom Build Stages](#custom-build-stages)
5. [Performance Tuning](#performance-tuning)
6. [Network Configuration](#network-configuration)
7. [Security Hardening](#security-hardening)

## Basic Customization

### Step 1: Copy User Configuration Template

```bash
cd build-system/config
cp user.conf.example user.conf
```

### Step 2: Edit Configuration

Open `user.conf` in your favorite editor:

```bash
vim user.conf  # or nano, code, etc.
```

### Step 3: Set Basic Options

```bash
# System settings
RPI_USERNAME="myuser"
RPI_PASSWORD="mysecurepassword"
HOSTNAME="my-projection-mapper"
TIMEZONE="America/Los_Angeles"

# Auto-start configuration
AUTOSTART_ENABLED="true"
AUTOSTART_PROJECT="example_simpler"
AUTOSTART_FULLSCREEN="true"
```

### Step 4: Build with Custom Configuration

```bash
cd ../pi-gen-method
sudo ./build.sh --config ../config/user.conf
```

## Advanced Configuration

### Display Settings

Configure resolution and display options:

```bash
# Force specific resolution
SCREEN_WIDTH="1920"
SCREEN_HEIGHT="1080"

# HDMI settings
HDMI_FORCE_HOTPLUG="1"  # Force HDMI even if no display detected
HDMI_DRIVE="2"          # 1=DVI, 2=HDMI with audio
```

### openFrameworks Version

Use a different openFrameworks version:

```bash
OF_VERSION="0.11.2"
OF_PLATFORM="linuxarmv7l"
OF_DOWNLOAD_URL="https://github.com/openframeworks/openFrameworks/releases/download/${OF_VERSION}/of_v${OF_VERSION}_${OF_PLATFORM}_release.tar.gz"
```

### WiFi Pre-configuration

Set up WiFi credentials (will connect automatically):

```bash
WIFI_SSID="MyNetwork"
WIFI_PASSWORD="MyNetworkPassword"
WIFI_COUNTRY="US"
```

## Adding Custom Software

### Additional System Packages

Add packages to be installed automatically:

```bash
# In user.conf
EXTRA_SYSTEM_PACKAGES=(
    "vim"
    "tmux"
    "htop"
    "iotop"
    "net-tools"
    "ffmpeg"
)

# Modify install-dependencies.sh to include these
# Or create a post-install script
```

### Custom openFrameworks Addons

Add additional addons to your build:

```bash
# In user.conf
CUSTOM_ADDONS=(
    "https://github.com/username/ofxCustomAddon.git|master|ofxCustomAddon"
    "https://github.com/username/ofxAnotherAddon.git|develop|ofxAnotherAddon"
)
```

Then modify `install-ofxpimapper.sh` to install these addons, or create a post-installation script.

### Post-Installation Scripts

Create custom scripts to run after installation:

```bash
# 1. Create your custom script
cat > ../config/my-custom-setup.sh <<'EOF'
#!/bin/bash
# My custom setup script

# Install additional software
apt-get install -y my-package

# Configure something
echo "my_config=value" > /etc/my-config.conf

# etc.
EOF

chmod +x ../config/my-custom-setup.sh

# 2. Add to user.conf
POST_INSTALL_SCRIPTS=(
    "../config/my-custom-setup.sh"
    "../config/another-script.sh"
)
```

## Custom Build Stages

For pi-gen builds, you can create custom stages:

### Step 1: Create Stage Directory

```bash
mkdir -p pi-gen-method/pi-gen/stage-custom
```

### Step 2: Create Stage Structure

```bash
cd pi-gen-method/pi-gen/stage-custom

# Create prerun script
cat > prerun.sh <<'EOF'
#!/bin/bash
echo "Running custom stage..."
EOF
chmod +x prerun.sh

# Create installation step
mkdir -p 00-my-custom-install

cat > 00-my-custom-install/00-run.sh <<'EOF'
#!/bin/bash -e

on_chroot << 'EOFCHROOT'
# Commands to run inside the image

# Install something
apt-get install -y my-package

# Configure something
echo "config=value" > /etc/myconfig

EOFCHROOT
EOF

chmod +x 00-my-custom-install/00-run.sh
```

### Step 3: Update Build Configuration

Edit `pi-gen-method/build.sh` and modify the `STAGE_LIST`:

```bash
STAGE_LIST="stage0 stage1 stage2 stage-ofxpimapper stage-custom"
```

## Performance Tuning

### GPU Memory

Allocate more GPU memory for better graphics performance:

```bash
GPU_MEM="384"  # Default is 256MB
```

### CPU Performance

Set CPU governor for maximum performance:

```bash
CPU_GOVERNOR="performance"  # Options: ondemand, performance, powersave
```

### Disable Swap

Improve SD card longevity and performance:

```bash
DISABLE_SWAP="true"
```

### Overclocking (Use with Caution)

```bash
ENABLE_OVERCLOCK="true"
OVERCLOCK_ARM_FREQ="2000"  # MHz
OVERCLOCK_GPU_FREQ="750"   # MHz
```

**Warning:** Overclocking may:
- Void your Raspberry Pi warranty
- Cause instability
- Reduce hardware lifespan
- Require better cooling

## Network Configuration

### Static IP Address

Create a custom script to configure static IP:

```bash
cat > config/setup-static-ip.sh <<'EOF'
#!/bin/bash
# Setup static IP address

cat > /etc/dhcpcd.conf <<EOFDCHP
interface eth0
static ip_address=192.168.1.100/24
static routers=192.168.1.1
static domain_name_servers=192.168.1.1 8.8.8.8
EOFDCHP
EOF

chmod +x config/setup-static-ip.sh

# Add to POST_INSTALL_SCRIPTS in user.conf
```

### Hostname Resolution

Configure mDNS for easy network access:

```bash
# The image will be accessible via:
# hostname.local (e.g., ofxpimapper.local)

# This is already configured if using Raspberry Pi OS
# To change hostname:
HOSTNAME="my-mapper"
```

## Security Hardening

### Change Default Credentials

**Always** change default username and password:

```bash
RPI_USERNAME="myuser"
RPI_PASSWORD="Str0ng!P@ssw0rd"
```

### Disable Password-less Sudo

```bash
# Do NOT set this to true in production:
DISABLE_SUDO_PASSWORD="false"
```

### Configure Firewall

Create a custom script:

```bash
cat > config/setup-firewall.sh <<'EOF'
#!/bin/bash
# Setup basic firewall

apt-get install -y ufw

# Default policies
ufw default deny incoming
ufw default allow outgoing

# Allow SSH
ufw allow 22/tcp

# Allow VNC (if enabled)
# ufw allow 5900/tcp

# Enable firewall
ufw --force enable
EOF

chmod +x config/setup-firewall.sh
```

### Disable Unnecessary Services

```bash
cat > config/disable-services.sh <<'EOF'
#!/bin/bash
# Disable unnecessary services

systemctl disable bluetooth
systemctl disable avahi-daemon
# Add more as needed
EOF

chmod +x config/disable-services.sh
```

## Example Configurations

### Minimal Performance Build

```bash
# user.conf for minimal performance build

# Basic settings
RPI_USERNAME="mapper"
HOSTNAME="mapper-minimal"

# Use lite base for smaller size
BASE_IMAGE="lite"

# Disable auto-start (manual control)
AUTOSTART_ENABLED="false"

# Performance
GPU_MEM="384"
CPU_GOVERNOR="performance"
DISABLE_SWAP="true"

# No extras
INCLUDE_SAMPLE_MEDIA="false"
```

### Full-Featured Production Build

```bash
# user.conf for production build

# Security
RPI_USERNAME="projector"
RPI_PASSWORD="VerySecurePassword123!"
HOSTNAME="production-mapper"

# Full desktop
BASE_IMAGE="desktop"

# Auto-start enabled
AUTOSTART_ENABLED="true"
AUTOSTART_PROJECT="example_simpler"
AUTOSTART_FULLSCREEN="true"
AUTOSTART_RESTART_ON_CRASH="true"

# Network
WIFI_SSID="VenueNetwork"
WIFI_PASSWORD="VenuePassword"
ENABLE_SSH="true"
ENABLE_VNC="true"

# Performance
GPU_MEM="384"
CPU_GOVERNOR="performance"

# Include samples
INCLUDE_SAMPLE_MEDIA="true"
```

### Development Build

```bash
# user.conf for development

# Convenient settings
RPI_USERNAME="dev"
RPI_PASSWORD="dev"
HOSTNAME="mapper-dev"
DISABLE_SUDO_PASSWORD="true"  # Convenient for dev, not for production

# Desktop for development
BASE_IMAGE="desktop"

# No auto-start (manual testing)
AUTOSTART_ENABLED="false"

# Extra tools
EXTRA_SYSTEM_PACKAGES=(
    "vim"
    "tmux"
    "git-gui"
    "meld"
    "gdb"
    "valgrind"
)

# Moderate performance
GPU_MEM="256"
CPU_GOVERNOR="ondemand"
```

## Testing Custom Configurations

1. **Always test in QEMU first:**
   ```bash
   cd testing
   ./test-qemu.sh ../pi-gen-method/deploy/image.img
   ```

2. **Verify all customizations:**
   - Check installed packages
   - Verify configuration files
   - Test network settings
   - Confirm performance settings

3. **Test on physical hardware:**
   - Use a spare SD card first
   - Test all features systematically
   - Use the testing checklist

## Troubleshooting

### Build Fails

- Check build logs in `pi-gen-method/pi-gen/work/*/build.log`
- Ensure sufficient disk space (25GB+)
- Verify all script paths are correct
- Check internet connectivity for downloads

### Configuration Not Applied

- Ensure you're using `--config` flag when building
- Verify configuration file has no syntax errors
- Check that variables are properly exported
- Review build logs for errors

### Scripts Not Running

- Verify scripts are executable (`chmod +x`)
- Check script shebang line (`#!/bin/bash`)
- Ensure proper error handling in scripts
- Test scripts independently first

## Best Practices

1. **Version Control:** Keep your `user.conf` in version control
2. **Documentation:** Document your customizations
3. **Testing:** Always test before deploying to production
4. **Backups:** Keep backup copies of working images
5. **Security:** Never commit passwords to version control
6. **Modularity:** Use separate scripts for different customizations
7. **Idempotency:** Ensure scripts can run multiple times safely

## Additional Resources

- [Raspberry Pi Configuration Documentation](https://www.raspberrypi.com/documentation/computers/configuration.html)
- [pi-gen Documentation](https://github.com/RPi-Distro/pi-gen)
- [openFrameworks Setup Guides](https://openframeworks.cc/setup/raspberrypi/)
- [ofxPiMapper Documentation](https://ofxpimapper.com/)
