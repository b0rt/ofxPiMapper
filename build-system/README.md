# ofxPiMapper Automated Build System

This directory contains automated build scripts for generating bootable Raspberry Pi 4 images pre-configured with ofxPiMapper and all dependencies.

## Quick Start

### Linux / macOS

```bash
# Method A: Using pi-gen (Recommended)
cd build-system/pi-gen-method
sudo ./build.sh

# Method B: Using Packer + QEMU (Cross-platform)
cd build-system/packer-method
./build.sh
```

### Windows (WSL2)

**First time setup - IMPORTANT:**

```bash
# Configure Git to prevent line-ending issues
git config --global core.autocrlf input
git config --global core.eol lf

# Install required packages
sudo apt update
sudo apt install -y git curl quilt parted qemu-user-static debootstrap zerofree \
    zip dosfstools libarchive-tools libcap2-bin grep rsync xz-utils file bc qemu-utils kpartx

# Clone repository in WSL2 native filesystem (not /mnt/c/)
cd ~
git clone https://github.com/b0rt/ofxPiMapper.git
cd ofxPiMapper/build-system/pi-gen-method

# Build
sudo ./build.sh
```

**For detailed WSL2 setup and troubleshooting, see [docs/WSL2-SETUP.md](docs/WSL2-SETUP.md)**

## Overview

The build system provides two methods for creating custom Raspberry Pi images:

### Method A: pi-gen (Official Raspberry Pi Image Builder)
- **Pros**: Official method, most reliable, produces production-ready images
- **Cons**: Requires Linux host or Docker, longer build time
- **Build Time**: ~2-4 hours (depending on hardware)
- **Final Image Size**: ~3.5-4.5 GB

### Method B: Packer + QEMU
- **Pros**: Cross-platform (Linux/macOS/Windows), reproducible builds
- **Cons**: Slower emulation, requires more RAM
- **Build Time**: ~3-5 hours (emulation overhead)
- **Final Image Size**: ~3.5-4.5 GB

## Directory Structure

```
build-system/
├── README.md                           # This file
├── config/                             # Configuration files
│   ├── build.conf                      # Main build configuration
│   ├── user.conf.example               # User customization example
│   └── media-samples/                  # Test media files
├── pi-gen-method/                      # Method A: pi-gen based build
│   ├── build.sh                        # Main build script
│   ├── config                          # pi-gen configuration
│   └── stages/                         # Custom build stages
│       └── stage-ofxpimapper/          # ofxPiMapper installation stage
├── packer-method/                      # Method B: Packer + QEMU
│   ├── build.sh                        # Packer build wrapper
│   ├── rpi4-ofxpimapper.pkr.hcl        # Packer template
│   └── scripts/                        # Provisioning scripts
├── scripts/                            # Shared installation scripts
│   ├── install-openframeworks.sh       # Install openFrameworks 0.12.0+
│   ├── install-dependencies.sh         # Install system dependencies
│   ├── install-ofxpimapper.sh          # Install ofxPiMapper and addons
│   ├── configure-x11.sh                # Force X11 display server
│   ├── configure-autologin.sh          # Setup auto-login
│   ├── configure-autostart.sh          # Setup auto-start on boot
│   └── compile-examples.sh             # Compile ofxPiMapper examples
├── testing/                            # Testing and validation
│   ├── test-qemu.sh                    # Test image in QEMU
│   ├── test-checklist.md               # Testing checklist
│   └── qemu-config/                    # QEMU configuration files
└── docs/                               # Documentation
    ├── CUSTOMIZATION.md                # How to customize builds
    ├── TROUBLESHOOTING.md              # Common issues and solutions
    └── ARCHITECTURE.md                 # Build system architecture
```

## System Requirements

### For pi-gen Method (Linux Host)
- Ubuntu 20.04+ or Debian 11+ (or Docker)
- 25GB free disk space
- 4GB+ RAM
- Packages: `git curl quilt parted qemu-user-static debootstrap zerofree zip dosfstools libarchive-tools libcap2-bin grep rsync xz-utils file git curl bc qemu-utils kpartx`

### For Windows Users (WSL2)
- **See detailed setup guide**: [docs/WSL2-SETUP.md](docs/WSL2-SETUP.md)
- WSL2 with Ubuntu 22.04 recommended
- 25GB free disk space in WSL2 filesystem
- 8GB+ RAM allocated to WSL2
- **Important**: Configure Git with `core.autocrlf=input` and `core.eol=lf` to prevent line-ending issues

### For Packer Method (Cross-platform)
- Packer 1.8.0+
- QEMU 6.0+
- 30GB free disk space
- 8GB+ RAM recommended

## Configuration

### Basic Configuration

Edit `config/build.conf` to customize your build:

```bash
# System settings
RPI_USERNAME="mapper"
RPI_PASSWORD="projection"
HOSTNAME="ofxpimapper"

# openFrameworks version
OF_VERSION="0.12.0"
OF_PLATFORM="linuxarmv7l"  # or "linuxaarch64" for 64-bit

# Auto-start settings
AUTOSTART_ENABLED="true"
AUTOSTART_FULLSCREEN="true"
AUTOSTART_PROJECT="example_simpler"

# Display settings
FORCE_X11="true"
ENABLE_AUTOLOGIN="true"
```

### Advanced Customization

Copy `config/user.conf.example` to `config/user.conf` and customize:

```bash
# Additional packages to install
EXTRA_PACKAGES="vim htop tmux"

# Custom git repositories to clone
CUSTOM_REPOS=(
    "https://github.com/yourusername/custom-addon.git"
)

# Post-installation scripts
POST_INSTALL_SCRIPTS=(
    "/path/to/custom-script.sh"
)
```

## Build Process

### Method A: Using pi-gen

```bash
cd build-system/pi-gen-method

# Option 1: Build on Linux host
sudo ./build.sh

# Option 2: Build using Docker (recommended)
sudo ./build.sh --docker

# Option 3: Build with custom config
sudo ./build.sh --config ../config/user.conf
```

The script will:
1. Clone/update pi-gen repository
2. Apply ofxPiMapper customizations
3. Build base Raspberry Pi OS
4. Install openFrameworks and dependencies
5. Clone and compile ofxPiMapper
6. Configure X11, auto-login, and auto-start
7. Generate final `.img` file in `deploy/`

### Method B: Using Packer

```bash
cd build-system/packer-method

# Build the image
./build.sh

# Build with custom variables
./build.sh --var 'rpi_username=myuser' --var 'rpi_password=mypass'
```

## Testing in QEMU

Before flashing to an SD card, test your image in QEMU:

```bash
cd build-system/testing
./test-qemu.sh ../pi-gen-method/deploy/image.img

# Or with custom options
./test-qemu.sh --image path/to/image.img --memory 2048 --vnc 5900
```

Access the running system:
- **VNC**: Connect to `localhost:5900` (password: same as RPI_PASSWORD)
- **SSH**: `ssh mapper@localhost -p 5022`

## Flashing to SD Card

After testing, flash the image to an SD card:

```bash
# Linux
sudo dd if=deploy/ofxpimapper-rpi4.img of=/dev/sdX bs=4M status=progress conv=fsync

# macOS
sudo dd if=deploy/ofxpimapper-rpi4.img of=/dev/rdiskX bs=4m

# Windows - use Raspberry Pi Imager or Etcher
# https://www.raspberrypi.com/software/
```

## First Boot

1. Insert SD card into Raspberry Pi 4
2. Connect HDMI display, keyboard, and mouse
3. Power on the device
4. System will boot to desktop (username: `mapper`)
5. ofxPiMapper will auto-start if `AUTOSTART_ENABLED=true`

### Default Credentials
- **Username**: `mapper` (or custom from config)
- **Password**: `projection` (or custom from config)

## Usage

### Manual Start
```bash
cd ~/openFrameworks/addons/ofxPiMapper/example_simpler
./bin/example_simpler -f
```

### Auto-start Configuration
The auto-start script is located at:
```
~/.config/autostart/ofxpimapper.desktop
```

To disable auto-start:
```bash
rm ~/.config/autostart/ofxpimapper.desktop
```

## Adding Custom Media

Place your media files in:
```
~/openFrameworks/addons/ofxPiMapper/example_simpler/bin/data/sources/
├── videos/
└── images/
```

Supported formats:
- **Video**: `.mp4`, `.mov`, `.mkv` (see encoding guidelines in main README)
- **Images**: `.jpg`, `.jpeg`, `.png`

## Build Artifacts

Successful builds produce:
- `deploy/ofxpimapper-rpi4-YYYY-MM-DD.img` - Flashable disk image
- `deploy/ofxpimapper-rpi4-YYYY-MM-DD.img.zip` - Compressed image
- `deploy/build.log` - Complete build log
- `deploy/sha256sum.txt` - Image checksums

## Troubleshooting

### Build fails with "No space left on device"
Ensure at least 25GB free space. Clean previous builds:
```bash
sudo ./build.sh --clean
```

### QEMU test shows black screen
Wait 2-3 minutes for initial boot. Check VNC connection and X11 configuration.

### ofxPiMapper doesn't compile
Check `deploy/build.log` for compilation errors. Verify openFrameworks installation.

### Video playback issues
Ensure videos are encoded correctly (see main README). Check audio settings with `alsamixer`.

For more troubleshooting, see `docs/TROUBLESHOOTING.md`.

## Development Workflow

### Iterative Development
```bash
# Make changes to scripts
vim scripts/install-ofxpimapper.sh

# Rebuild only the ofxPiMapper stage
sudo ./build.sh --stage stage-ofxpimapper

# Test in QEMU
cd ../testing
./test-qemu.sh ../pi-gen-method/deploy/image.img
```

### Custom Stages
Add custom installation stages in `pi-gen-method/stages/stage-custom/`:
```
stage-custom/
├── 00-install-package/
│   └── 00-run.sh
└── prerun.sh
```

## Contributing

Improvements to the build system are welcome! Please ensure:
1. Scripts are idempotent (can be run multiple times)
2. Errors are handled gracefully
3. Documentation is updated
4. Testing procedures are followed

## License

This build system is part of ofxPiMapper and follows the same MIT License.

## Credits

- ofxPiMapper: Krisjanis Rijnieks
- Build system: Built on pi-gen by Raspberry Pi Foundation
- This fork maintained by: b0rt

## Support

- Issues: https://github.com/b0rt/ofxPiMapper/issues
- Discussions: https://gitter.im/kr15h/ofxPiMapper
- Documentation: https://ofxpimapper.com
