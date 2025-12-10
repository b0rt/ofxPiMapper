# Removed Packages Documentation

## Overview

This document lists packages that are automatically removed from the pi-gen build process because they are not available in the Debian Bookworm repositories. These packages are part of the official Raspberry Pi OS build scripts but cannot be installed when building custom images using pi-gen.

## Why Packages Are Removed

The official Raspberry Pi OS images include proprietary or Raspberry Pi-specific packages that are hosted in custom repositories. When building custom images with pi-gen using standard Debian Bookworm repositories, these packages are not available and cause build failures with errors like:

```
E: Unable to locate package <package-name>
```

Our build system automatically removes these packages from the pi-gen package lists before building to ensure a successful build process.

## List of Removed Packages

### Stage 2 Packages (System Setup)

| Package | Original Location | Description |
|---------|------------------|-------------|
| `rpi-swap` | stage2/01-sys-tweaks/00-packages | Raspberry Pi swap file management utility |
| `rpi-loop-utils` | stage2/01-sys-tweaks/00-packages | Raspberry Pi loop device utilities |
| `rpi-usb-gadget` | stage2 subdirectories | USB gadget mode configuration for Pi Zero |
| `rpi-cloud-init-mods` | stage2/04-cloud-init/00-packages | Raspberry Pi-specific cloud-init modifications |

### Stage 3 Packages (Desktop Environment)

| Package | Original Location | Description |
|---------|------------------|-------------|
| `rpd-wayland-core` | stage3/00-install-packages/00-packages-nr | Raspberry Pi Desktop Wayland core components |
| `rpd-x-core` | stage3/00-install-packages/00-packages-nr | Raspberry Pi Desktop X11 core components |
| `rpd-preferences` | stage3/00-install-packages/00-packages | Raspberry Pi Desktop preferences/settings tools |
| `rpd-theme` | stage3/00-install-packages/00-packages | Raspberry Pi Desktop theme and appearance packages |

## How Removal Works

The build script (`build-system/pi-gen-method/build.sh`) automatically removes these packages using the following process:

1. **Package List Discovery**: Uses `find` command to locate all package files:
   ```bash
   find "${PIGEN_DIR}/stage2" "${PIGEN_DIR}/stage3" \
     -type f \( -name "00-packages" -o -name "00-packages-nr" \)
   ```

2. **Surgical Removal**: Removes only the specific package names from lines, preserving other packages on the same line:
   - Removes package at start of line: `s/^${pkg}[[:space:]]\+//g`
   - Removes package at end of line: `s/[[:space:]]\+${pkg}$//g`
   - Removes package in middle of line: `s/[[:space:]]\+${pkg}[[:space:]]\+/ /g`
   - Removes package when alone on line: `/^${pkg}$/d`
   - Cleans up empty lines: `/^[[:space:]]*$/d`

3. **Logging**: Reports which files were processed and how many packages were removed

## Impact on Final Image

Removing these packages has the following effects on the final image:

### Minimal Impact

- **rpi-swap**: Standard Linux swap mechanisms still work; only loses Pi-specific swap optimization
- **rpi-loop-utils**: Standard loop device tools are available
- **rpd-theme**: Standard Raspberry Pi Desktop theme is available through other packages

### Functionality Removed

- **rpi-usb-gadget**: USB gadget mode for Pi Zero requires manual configuration
- **rpi-cloud-init-mods**: Pi-specific cloud-init features not available
- **rpd-wayland-core**: Wayland support may be limited to standard Debian packages
- **rpd-x-core**: X11 environment uses standard Debian packages instead of Pi-optimized versions
- **rpd-preferences**: Some Raspberry Pi-specific configuration tools not available

## Alternative Solutions

If you need functionality from these packages, consider:

1. **Add Custom Repositories**: Configure the official Raspberry Pi repositories in your pi-gen config
   ```bash
   # Add to stage2/01-sys-tweaks/00-packages-repos
   deb http://archive.raspberrypi.org/debian/ bookworm main
   ```

2. **Manual Installation**: Install packages after image creation via SSH
   ```bash
   sudo apt-get update
   sudo apt-get install rpi-swap rpi-loop-utils
   ```

3. **Replace with Standard Debian Packages**: Add equivalent Debian packages to your custom stage
   ```bash
   # For printing support (replaces rpd-* CUPS functionality):
   cups cups-client system-config-printer

   # For desktop environment (replaces rpd-wayland-core/rpd-x-core):
   xserver-xorg xserver-xorg-video-fbdev
   lightdm lxde-core

   # For desktop theming (replaces rpd-theme/rpd-preferences):
   lxappearance
   ```

4. **Custom Scripts**: Replicate functionality using shell scripts in stage customizations

## Related Issues

This package removal addresses the following build failures:

- "Unable to locate package rpi-swap" in stage2/01-sys-tweaks
- "Unable to locate package rpi-loop-utils" in stage2/01-sys-tweaks
- "Unable to locate package rpi-usb-gadget" in stage2
- "Unable to locate package rpi-cloud-init-mods" in stage2/04-cloud-init
- "Unable to locate package rpd-wayland-core" in stage3/00-install-packages
- "Unable to locate package rpd-x-core" in stage3/00-install-packages
- "Unable to locate package rpd-preferences" in stage3/00-install-packages
- "Unable to locate package rpd-theme" in stage3/00-install-packages

## Additional Fixes

The build script also includes fixes for related errors caused by missing packages:

### 1. rpi-resize.service Fix

**Issue**: `Failed to enable unit, unit rpi-resize.service does not exist`

**Location**: `stage2/01-sys-tweaks/01-run.sh`

**Fix**: Conditionally enables the service only if it exists:
```bash
systemctl list-unit-files rpi-resize.service --no-pager 2>/dev/null | \
  grep -q rpi-resize.service && \
  systemctl enable rpi-resize.service || \
  echo "rpi-resize.service not found, skipping"
```

### 2. lpadmin Group Fix

**Issue**: `adduser: The group 'lpadmin' does not exist.`

**Location**: `stage3/01-print-support/00-run.sh`

**Root Cause**: The `lpadmin` group is created by the CUPS printing system, which is normally bundled in the `rpd-*` desktop packages. Since we remove all `rpd-*` packages (rpd-wayland-core, rpd-x-core, rpd-preferences, rpd-theme), CUPS is not installed and the lpadmin group doesn't exist.

**Fix**: Conditionally adds the user to lpadmin group only if it exists:
```bash
getent group lpadmin >/dev/null && \
  adduser "$FIRST_USER_NAME" lpadmin || \
  echo "lpadmin group not found (CUPS not installed), skipping"
```

**Note**: If you need printing support, you should add standard Debian CUPS packages to your custom stage. See the Alternative Solutions section for details.

## References

- pi-gen repository: https://github.com/RPi-Distro/pi-gen
- Raspberry Pi package repository: http://archive.raspberrypi.org/debian/
- Build script location: `/home/user/ofxPiMapper/build-system/pi-gen-method/build.sh`
- Package removal logic: Lines 517-614 in build.sh

## Maintenance

When updating pi-gen or building with newer Debian versions, you may encounter additional missing packages. To add new packages to the removal list:

1. Edit `build-system/pi-gen-method/build.sh`
2. Add package name to the `UNAVAILABLE_PACKAGES` array (around line 524)
3. Update this documentation with the new package details
4. Test the build to ensure successful completion

## Version History

- **2025-12-10**: Initial documentation created
  - 8 packages documented across stage2 and stage3
  - Includes rpi-* and rpd-* package families
  - Debian Bookworm compatibility focus
