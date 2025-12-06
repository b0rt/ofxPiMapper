# Quick Start Guide

Get started building your custom ofxPiMapper Raspberry Pi image in 5 minutes!

## Prerequisites

### For pi-gen method (Linux)
```bash
# Ubuntu/Debian
sudo apt-get install git curl quilt parted qemu-user-static debootstrap \
    zerofree zip dosfstools libarchive-tools libcap2-bin grep rsync \
    xz-utils file git curl bc qemu-utils kpartx
```

### For Packer method (Cross-platform)
```bash
# Install Packer
# Visit: https://www.packer.io/downloads

# Install QEMU
# Ubuntu/Debian:
sudo apt-get install qemu-system-arm qemu-user-static

# macOS:
brew install qemu
```

## Method A: pi-gen (Recommended for Linux)

### Step 1: Clone and Navigate
```bash
git clone https://github.com/b0rt/ofxPiMapper.git
cd ofxPiMapper/build-system/pi-gen-method
```

### Step 2: Build
```bash
# Basic build (takes 2-4 hours)
sudo ./build.sh

# Or with Docker (no root needed, but Docker must be installed)
./build.sh --docker
```

### Step 3: Find Your Image
```bash
ls -lh deploy/*.img
```

## Method B: Packer (Cross-platform)

### Step 1: Install Packer Plugin
```bash
cd ofxPiMapper/build-system/packer-method
packer plugins install github.com/mkaczanowski/arm
```

### Step 2: Build
```bash
./build.sh
```

### Step 3: Find Your Image
```bash
ls -lh deploy/*.img
```

## Customize Your Build

### Quick Customization
```bash
cd build-system/config
cp user.conf.example user.conf
vim user.conf  # Edit your settings
```

Example user.conf:
```bash
# Basic settings
RPI_USERNAME="mymapper"
RPI_PASSWORD="mypassword"
HOSTNAME="projection-mapper"

# Enable auto-start
AUTOSTART_ENABLED="true"
AUTOSTART_PROJECT="example_simpler"
AUTOSTART_FULLSCREEN="true"
```

### Build with Custom Config
```bash
cd ../pi-gen-method
sudo ./build.sh --config ../config/user.conf
```

## Test Your Image

### In QEMU (Before Flashing)
```bash
cd ../testing
./test-qemu.sh ../pi-gen-method/deploy/your-image.img

# Connect via VNC: localhost:5900
# Or SSH: ssh -p 5022 mapper@localhost
```

## Flash to SD Card

### Linux
```bash
# Find your SD card
lsblk

# Flash (replace sdX with your SD card device)
sudo dd if=deploy/image.img of=/dev/sdX bs=4M status=progress conv=fsync
```

### macOS
```bash
# Find your SD card
diskutil list

# Flash (replace diskX with your SD card)
sudo dd if=deploy/image.img of=/dev/rdiskX bs=4m
```

### Windows
Use [Raspberry Pi Imager](https://www.raspberrypi.com/software/) or [Etcher](https://www.balena.io/etcher/)

## First Boot

1. Insert SD card into Raspberry Pi 4
2. Connect HDMI, keyboard, mouse
3. Power on
4. Login (default: user=`mapper`, pass=`projection`)
5. ofxPiMapper should auto-start (if enabled)

### Manual Start
```bash
cd ~/openFrameworks/addons/ofxPiMapper/example_simpler
./bin/example_simpler -f
```

## Next Steps

- Add your media to: `~/openFrameworks/addons/ofxPiMapper/example_simpler/bin/data/sources/`
- Read the full [README](README.md) for detailed documentation
- See [CUSTOMIZATION.md](docs/CUSTOMIZATION.md) for advanced options
- Check [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) if you encounter issues

## Common Tasks

### Stop Auto-start
```bash
~/disable-autostart.sh
```

### Check Status
```bash
~/status-ofxpimapper.sh
```

### Change WiFi
```bash
sudo raspi-config
# System Options -> Wireless LAN
```

### Update System
```bash
sudo apt-get update
sudo apt-get upgrade
```

## Getting Help

- Issues: https://github.com/b0rt/ofxPiMapper/issues
- Chat: https://gitter.im/kr15h/ofxPiMapper
- Docs: docs/ directory

## Estimated Times

- Build time: 2-5 hours (depending on method and hardware)
- Flash time: 10-30 minutes (depending on SD card)
- First boot: 2-3 minutes
- Total: ~3-6 hours for first complete build

## Tips

- Use a fast SD card (Class 10 or better)
- Ensure good internet connection for downloads
- Have at least 25GB free disk space
- Use QEMU testing to save SD card writes
- Keep your `user.conf` in version control (without passwords!)
