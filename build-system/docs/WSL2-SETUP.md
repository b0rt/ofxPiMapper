# WSL2 Setup Guide for ofxPiMapper Build System

This guide explains how to set up and use the ofxPiMapper build system on Windows using WSL2 (Windows Subsystem for Linux 2).

## Prerequisites

### 1. Install WSL2

If you haven't installed WSL2 yet:

```powershell
# Open PowerShell as Administrator
wsl --install
# Or for a specific distribution
wsl --install -d Ubuntu-22.04
```

Restart your computer after installation.

### 2. Configure Git for WSL2

**IMPORTANT**: To prevent line-ending issues, configure Git properly in WSL2:

```bash
# Inside WSL2 terminal
git config --global core.autocrlf input
git config --global core.eol lf
```

This ensures that:
- Files are checked out with LF (Unix) line endings
- Files are committed with LF line endings
- Shell scripts and configuration files work correctly

### 3. Clone the Repository

**Method 1: Clone directly in WSL2 (Recommended)**

```bash
cd ~
mkdir -p workspace-github
cd workspace-github
git clone https://github.com/b0rt/ofxPiMapper.git
cd ofxPiMapper
```

**Method 2: If already cloned on Windows**

If you already cloned the repository on Windows and are accessing it from WSL2:

```bash
# Navigate to your Windows repository
cd /mnt/c/Users/YourUsername/path/to/ofxPiMapper

# Re-normalize line endings
git rm --cached -r .
git reset --hard HEAD
```

## System Setup

### Install Required Packages

```bash
sudo apt update
sudo apt install -y \
    git curl quilt parted qemu-user-static debootstrap zerofree zip \
    dosfstools libarchive-tools libcap2-bin grep rsync xz-utils file \
    bc qemu-utils kpartx
```

### Verify Installation

```bash
# Check that QEMU user static is installed
ls -la /usr/bin/qemu-*-static

# Verify binfmt support
systemctl status binfmt-support
```

## Building the Image

### Quick Start

```bash
cd ~/workspace-github/ofxPiMapper/build-system/pi-gen-method
sudo ./build.sh
```

### If You Encounter Line-Ending Errors

If you see errors like:
```
$'\r': command not found
```

This means some files still have Windows (CRLF) line endings. Fix with:

```bash
# Install dos2unix if not already installed
sudo apt install dos2unix

# Convert all shell scripts and config files
find ~/workspace-github/ofxPiMapper/build-system -type f \( -name "*.sh" -o -name "*.conf" \) -exec dos2unix {} \;
```

However, with the `.gitattributes` file now in place, this should not be necessary for fresh clones.

## Common WSL2 Issues and Solutions

### Issue 1: "No such file or directory" when running ./build.sh

**Cause**: File has Windows line endings (CRLF) instead of Unix (LF)

**Solution**:
```bash
dos2unix ./build.sh
# Or normalize all at once
find . -type f -name "*.sh" -exec dos2unix {} \;
```

### Issue 2: Permission Denied

**Cause**: Script not executable

**Solution**:
```bash
chmod +x build.sh
# Or for all scripts
find . -type f -name "*.sh" -exec chmod +x {} \;
```

### Issue 3: Disk Space Issues

**Cause**: WSL2 virtual disk is full

**Solution**:
```bash
# Check available space
df -h

# Clean Docker images if using Docker method
docker system prune -a

# Compact WSL2 virtual disk (run in PowerShell as Administrator)
# First, shutdown WSL
wsl --shutdown

# Then compact the disk
Optimize-VHD -Path "$env:LOCALAPPDATA\Packages\CanonicalGroupLimited.Ubuntu22.04LTS_*\LocalState\ext4.vhdx" -Mode Full
```

### Issue 4: Build is Very Slow

**Cause**: I/O performance on /mnt/c/ is slower than native WSL2 filesystem

**Solution**: Always work in WSL2's native filesystem (`~` or `/home/username/`), not in `/mnt/c/`:

```bash
# ❌ Slow - accessing Windows filesystem
cd /mnt/c/Users/YourName/ofxPiMapper

# ✅ Fast - using WSL2 native filesystem
cd ~/workspace-github/ofxPiMapper
```

### Issue 5: systemd Services Not Running

**Cause**: systemd may not be enabled by default in WSL2

**Solution**:
```bash
# Enable systemd in WSL2 (Ubuntu 22.04+)
# Edit /etc/wsl.conf
sudo nano /etc/wsl.conf

# Add:
[boot]
systemd=true

# Save and exit, then restart WSL from PowerShell
wsl --shutdown
wsl
```

## Build Methods for WSL2

### Method 1: Native Build (Recommended for WSL2)

```bash
cd ~/workspace-github/ofxPiMapper/build-system/pi-gen-method
sudo ./build.sh
```

**Pros**:
- Fastest method on WSL2
- Uses native Linux kernel features

**Cons**:
- Requires sudo access
- Takes 2-4 hours

### Method 2: Docker Build

```bash
sudo ./build.sh --docker
```

**Pros**:
- Isolated build environment
- Reproducible builds

**Cons**:
- Requires Docker Desktop for Windows with WSL2 backend
- Slower than native

## Docker Desktop Configuration for WSL2

If using Docker method:

1. Install Docker Desktop for Windows
2. Enable WSL2 backend in Docker Desktop settings
3. Enable integration with your WSL2 distribution

```bash
# Verify Docker is accessible from WSL2
docker --version
docker ps
```

## Performance Tips

1. **Use WSL2 Native Filesystem**: Work in `~` not `/mnt/c/`
2. **Allocate More Resources**: Configure WSL2 resources in `%USERPROFILE%\.wslconfig`:

```ini
[wsl2]
memory=8GB
processors=4
swap=4GB
```

3. **Disable Windows Defender for WSL2 Files**:
   - Add exclusion for `%LOCALAPPDATA%\Packages\CanonicalGroupLimited.*`

## Accessing Build Artifacts

After build completes:

```bash
# View build artifacts
ls -lh ~/workspace-github/ofxPiMapper/build-system/pi-gen-method/deploy/

# Copy to Windows for flashing
cp deploy/*.img /mnt/c/Users/YourName/Downloads/
```

Then use Windows tools like:
- Raspberry Pi Imager
- balenaEtcher
- Win32DiskImager

## Testing in QEMU from WSL2

```bash
cd ~/workspace-github/ofxPiMapper/build-system/testing
./test-qemu.sh ../pi-gen-method/deploy/image.img

# Access via VNC from Windows
# Connect to: localhost:5900
# Or via SSH:
ssh -p 5022 mapper@localhost
```

## Troubleshooting Build Failures

### Enable Detailed Logging

```bash
# Run with verbose output
sudo bash -x ./build.sh 2>&1 | tee build-debug.log
```

### Check Build Logs

```bash
# View pi-gen build logs
tail -f ~/workspace-github/ofxPiMapper/build-system/pi-gen-method/pi-gen/work/build.log

# Check for specific errors
grep -i error ~/workspace-github/ofxPiMapper/build-system/pi-gen-method/pi-gen/work/build.log
```

### Clean and Retry

```bash
# Clean previous builds
sudo ./build.sh --clean

# Start fresh
sudo ./build.sh
```

## File Permissions

If you encounter permission issues:

```bash
# Fix ownership (replace 'yourusername' with your WSL username)
sudo chown -R yourusername:yourusername ~/workspace-github/ofxPiMapper

# Fix script permissions
find ~/workspace-github/ofxPiMapper/build-system -name "*.sh" -exec chmod +x {} \;
```

## Git Best Practices for WSL2

```bash
# Always use these settings in WSL2
git config --global core.autocrlf input
git config --global core.eol lf

# Verify settings
git config --get core.autocrlf  # Should show: input
git config --get core.eol       # Should show: lf

# If files still have CRLF after pull
git rm --cached -r .
git reset --hard HEAD
```

## Quick Reference

```bash
# Setup (once)
git config --global core.autocrlf input
git config --global core.eol lf
sudo apt install dos2unix

# Clone and build
cd ~
git clone https://github.com/b0rt/ofxPiMapper.git
cd ofxPiMapper/build-system/pi-gen-method
sudo ./build.sh

# If line-ending errors occur
find ../.. -name "*.sh" -exec dos2unix {} \;

# Copy result to Windows
cp deploy/*.img /mnt/c/Users/YourName/Downloads/
```

## Support

If you encounter issues not covered here:

1. Check main [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
2. Search existing [GitHub Issues](https://github.com/b0rt/ofxPiMapper/issues)
3. Create a new issue with:
   - WSL2 version: `wsl --version`
   - Ubuntu version: `lsb_release -a`
   - Error messages and logs
