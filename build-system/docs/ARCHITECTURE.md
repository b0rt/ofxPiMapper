# Build System Architecture

This document describes the architecture and design of the ofxPiMapper automated build system.

## Overview

The build system provides two main methods for creating custom Raspberry Pi images:

1. **pi-gen method** (Official, Linux-based)
2. **Packer method** (Cross-platform, QEMU-based)

Both methods produce functionally identical images with ofxPiMapper and dependencies pre-installed.

## Directory Structure

```
build-system/
├── README.md                     # Main documentation
├── config/                       # Configuration files
│   ├── build.conf                # Default build configuration
│   ├── user.conf.example         # User customization template
│   └── media-samples/            # Optional sample media files
├── scripts/                      # Shared installation scripts
│   ├── install-dependencies.sh   # System dependencies
│   ├── install-openframeworks.sh # openFrameworks installation
│   ├── install-ofxpimapper.sh    # ofxPiMapper and addons
│   ├── configure-x11.sh          # X11 display configuration
│   ├── configure-autologin.sh    # Auto-login setup
│   └── configure-autostart.sh    # Auto-start configuration
├── pi-gen-method/                # Method A: pi-gen builds
│   ├── build.sh                  # Main build script
│   ├── config                    # pi-gen configuration (generated)
│   ├── pi-gen/                   # pi-gen repository (cloned)
│   └── deploy/                   # Build artifacts
├── packer-method/                # Method B: Packer builds
│   ├── build.sh                  # Packer wrapper script
│   ├── rpi4-ofxpimapper.pkr.hcl  # Packer template
│   └── deploy/                   # Build artifacts
├── testing/                      # Testing and validation
│   ├── test-qemu.sh              # QEMU testing script
│   ├── test-checklist.md         # Manual testing checklist
│   └── qemu-config/              # QEMU kernels and configs
└── docs/                         # Documentation
    ├── CUSTOMIZATION.md          # Customization guide
    ├── TROUBLESHOOTING.md        # Troubleshooting guide
    └── ARCHITECTURE.md           # This file
```

## Build Flow

### Common Flow (Both Methods)

```
┌─────────────────────────────────────┐
│  Load Configuration                 │
│  (build.conf + user.conf)          │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│  Download Base Raspberry Pi OS      │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│  Install System Dependencies        │
│  (install-dependencies.sh)          │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│  Configure X11 Display              │
│  (configure-x11.sh)                 │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│  Configure Auto-login               │
│  (configure-autologin.sh)           │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│  Install openFrameworks             │
│  (install-openframeworks.sh)        │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│  Install ofxPiMapper & Addons       │
│  (install-ofxpimapper.sh)           │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│  Compile Examples                   │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│  Configure Auto-start (optional)    │
│  (configure-autostart.sh)           │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│  Finalize and Create Image          │
└─────────────────────────────────────┘
```

### pi-gen Method Specifics

```
pi-gen-method/build.sh
    │
    ├─> Load config/build.conf
    ├─> Clone/update pi-gen repository
    ├─> Create custom stage-ofxpimapper/
    │   ├─> 00-install-dependencies/
    │   ├─> 01-configure-x11/
    │   ├─> 02-configure-autologin/
    │   ├─> 03-install-openframeworks/
    │   ├─> 04-install-ofxpimapper/
    │   └─> 05-configure-autostart/
    ├─> Configure pi-gen (STAGE_LIST, etc.)
    ├─> Run pi-gen build process
    └─> Move artifacts to deploy/
```

### Packer Method Specifics

```
packer-method/build.sh
    │
    ├─> Load config/build.conf
    ├─> Validate rpi4-ofxpimapper.pkr.hcl
    ├─> Initialize Packer plugins
    └─> Run packer build
        │
        ├─> Download base image
        ├─> Start QEMU ARM emulation
        ├─> Run provisioning scripts:
        │   ├─> install-dependencies.sh
        │   ├─> configure-x11.sh
        │   ├─> configure-autologin.sh
        │   ├─> install-openframeworks.sh
        │   ├─> install-ofxpimapper.sh
        │   └─> configure-autostart.sh
        ├─> Post-process: compress, checksum
        └─> Output to deploy/
```

## Key Components

### Configuration System

#### build.conf
The default configuration file that defines all build parameters:
- System settings (username, password, hostname)
- Raspberry Pi OS version and architecture
- openFrameworks version and platform
- Network configuration
- Performance tuning
- Build options

#### user.conf
User-specific overrides that customize the build without modifying defaults. Loaded after `build.conf` and overrides matching variables.

**Design principle:** Separation of defaults and customizations allows:
- Easy updates to default config
- Version control of custom settings
- Multiple build profiles

### Installation Scripts

All installation scripts follow a common pattern:

```bash
#!/bin/bash
set -e  # Exit on error
set -u  # Exit on undefined variable

# Logging functions (log_info, log_warn, log_error)

# Load configuration from environment

# Main installation logic

# Verification and testing

# Summary output
```

**Design principles:**
- **Idempotent:** Can be run multiple times safely
- **Verbose:** Clear logging of all operations
- **Fail-fast:** Exit immediately on errors
- **Verifiable:** Check results after installation

### Build Scripts

#### pi-gen-method/build.sh

Responsibilities:
1. Clone and update pi-gen repository
2. Create custom installation stages
3. Configure pi-gen settings
4. Execute build process
5. Post-process artifacts

**Why pi-gen?**
- Official Raspberry Pi image builder
- Battle-tested and maintained
- Direct chroot access for installations
- Produces optimized images

**Limitations:**
- Requires Linux host (or Docker)
- Longer initial setup
- Requires root privileges

#### packer-method/build.sh

Responsibilities:
1. Validate Packer template
2. Install required plugins
3. Execute Packer build
4. Post-process artifacts

**Why Packer?**
- Cross-platform support
- Declarative configuration (HCL)
- Reproducible builds
- Good for CI/CD

**Limitations:**
- Slower (QEMU emulation overhead)
- Requires more resources
- Less direct control than pi-gen

### Testing Infrastructure

#### QEMU Testing

`test-qemu.sh` allows testing images before flashing:

**Process:**
1. Download Raspberry Pi kernel for QEMU
2. Extract partition offsets from image
3. Start QEMU with appropriate parameters
4. Provide VNC and SSH access

**Why QEMU testing?**
- No SD card writes until verified
- Faster iteration during development
- Automated testing capability
- Safe experimentation

**Limitations:**
- Slower than real hardware
- Not all hardware features available
- Display performance differs

## Design Decisions

### Modular Scripts

**Decision:** Separate scripts for each installation phase

**Rationale:**
- Easier to debug individual components
- Can be reused independently
- Simpler to test and maintain
- Users can customize specific parts

**Trade-off:** More files to manage

### Configuration Hierarchy

**Decision:** Two-tier configuration (build.conf + user.conf)

**Rationale:**
- Defaults can be updated without affecting user customizations
- Clear separation of "official" and "custom" settings
- Easy to share configurations

**Trade-off:** Need to understand which file to edit

### Two Build Methods

**Decision:** Support both pi-gen and Packer

**Rationale:**
- pi-gen: Best for Linux users, most reliable
- Packer: Best for cross-platform, CI/CD
- Different use cases benefit from different tools

**Trade-off:** More code to maintain

### Auto-start Flexibility

**Decision:** Multiple auto-start methods (systemd, XDG, LXDE)

**Rationale:**
- Ensures compatibility across different Raspberry Pi OS versions
- Redundancy increases reliability
- Users can choose preferred method

**Trade-off:** More complex configuration

## Extension Points

### Adding New Installation Steps

1. Create script in `scripts/`:
   ```bash
   scripts/install-mycustomthing.sh
   ```

2. For pi-gen, add to stage:
   ```bash
   mkdir stage-ofxpimapper/06-install-mycustomthing/
   # Add 00-run.sh that calls your script
   ```

3. For Packer, add provisioner to `.pkr.hcl`:
   ```hcl
   provisioner "file" {
     source      = "../scripts/install-mycustomthing.sh"
     destination = "/tmp/install-mycustomthing.sh"
   }
   provisioner "shell" {
     inline = ["bash /tmp/install-mycustomthing.sh"]
   }
   ```

### Adding Configuration Options

1. Add to `config/build.conf`:
   ```bash
   MY_NEW_OPTION="${MY_NEW_OPTION:-default_value}"
   export MY_NEW_OPTION
   ```

2. Use in scripts:
   ```bash
   if [ "${MY_NEW_OPTION}" = "some_value" ]; then
       # Do something
   fi
   ```

### Adding New Examples

Modify `install-ofxpimapper.sh`:
```bash
ADDITIONAL_EXAMPLES="example_basic example_fbo-sources my_custom_example"
```

## Security Considerations

### Credentials

- Default passwords should always be changed in production
- Never commit passwords to version control
- Use environment variables for sensitive data in CI/CD

### sudo Usage

- Installation scripts require root for system modifications
- Auto-start uses systemd user services when possible
- Option to disable password-less sudo

### Network

- SSH enabled by default for convenience (can be disabled)
- No firewall by default (can be added via custom scripts)
- VNC disabled by default (can be enabled)

## Performance Considerations

### Build Time

- pi-gen: 2-4 hours (native ARM compilation)
- Packer: 3-5 hours (QEMU emulation overhead)

**Optimization strategies:**
- Use ccache for faster recompilation
- Pre-download large files
- Parallel compilation where possible

### Image Size

- Base (Lite): ~2.5 GB
- Base (Desktop): ~3.5 GB
- With OF + ofxPiMapper: +500MB - 1GB
- Compressed: ~50-60% of original size

**Optimization strategies:**
- Remove unnecessary packages
- Clean apt cache
- Shrink filesystem to minimum size

### Runtime Performance

- GPU memory: 256MB minimum, 384MB recommended
- CPU governor: "performance" for consistent framerate
- Swap: Disabled for SD card longevity

## Future Enhancements

Potential improvements:

1. **CI/CD Integration:**
   - Automated builds on commit
   - Release artifacts to GitHub Releases
   - Automated testing in QEMU

2. **Web Interface:**
   - GUI for configuration
   - Progress monitoring
   - Download built images

3. **Additional Platforms:**
   - Raspberry Pi 3 support
   - Other ARM boards (NVIDIA Jetson, etc.)

4. **Cloud Builds:**
   - AWS/Azure/GCP build instances
   - Distributed builds for faster completion

5. **Incremental Updates:**
   - Update existing images instead of full rebuild
   - Patch system for security updates

## References

- [pi-gen Documentation](https://github.com/RPi-Distro/pi-gen)
- [Packer Documentation](https://www.packer.io/docs)
- [Raspberry Pi Documentation](https://www.raspberrypi.com/documentation/)
- [openFrameworks Raspberry Pi Setup](https://openframeworks.cc/setup/raspberrypi/)
- [ofxPiMapper GitHub](https://github.com/b0rt/ofxPiMapper)
