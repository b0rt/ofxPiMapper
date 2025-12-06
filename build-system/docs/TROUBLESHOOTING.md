# Troubleshooting Guide

This guide covers common issues and solutions when building, testing, and running custom ofxPiMapper Raspberry Pi images.

## Table of Contents

1. [Build Issues](#build-issues)
2. [Boot Issues](#boot-issues)
3. [Display Issues](#display-issues)
4. [ofxPiMapper Issues](#ofxpimapper-issues)
5. [Performance Issues](#performance-issues)
6. [Network Issues](#network-issues)
7. [Audio Issues](#audio-issues)
8. [QEMU Testing Issues](#qemu-testing-issues)

---

## Build Issues

### Problem: "No space left on device"

**Symptoms:** Build fails with disk space error

**Solution:**
```bash
# Check available space
df -h

# Clean previous builds
cd pi-gen-method
sudo ./build.sh --clean

# Remove unnecessary files
sudo apt-get clean
sudo apt-get autoremove

# Ensure at least 25GB free space
```

### Problem: Build fails during package installation

**Symptoms:** apt-get errors, package not found

**Solution:**
```bash
# Update package lists
sudo apt-get update

# Check internet connectivity
ping -c 4 google.com

# Try using different mirror in pi-gen config
# Edit pi-gen-method/pi-gen/config
APT_PROXY=http://your-apt-mirror.com
```

### Problem: openFrameworks download fails

**Symptoms:** wget/curl errors during OF download

**Solution:**
```bash
# Verify URL in config/build.conf
# Try manual download:
wget https://github.com/openframeworks/openFrameworks/releases/download/0.12.0/of_v0.12.0_linuxarmv7l_release.tar.gz

# If manual download works, check firewall/proxy settings
# Update OF_DOWNLOAD_URL in config if needed
```

### Problem: Compilation fails for openFrameworks

**Symptoms:** g++ errors, undefined references

**Solution:**
```bash
# Check build log for specific errors
tail -100 /tmp/of_compile.log

# Common fixes:
# 1. Insufficient RAM - increase PARALLEL_JOBS in config
PARALLEL_JOBS=1  # Instead of 4

# 2. Missing dependencies
sudo apt-get install build-essential g++ make

# 3. Corrupted download - remove and re-download OF
```

### Problem: ofxPiMapper won't compile

**Symptoms:** Addon errors, missing dependencies

**Solution:**
```bash
# Verify all required addons are installed
ls -la ~/openFrameworks/addons/ofxOMXPlayer
ls -la ~/openFrameworks/addons/ofxVideoSync

# Check addons.make file
cat ~/openFrameworks/addons/ofxPiMapper/example_simpler/addons.make

# Manually compile with verbose output
cd ~/openFrameworks/addons/ofxPiMapper/example_simpler
make V=1
```

---

## Boot Issues

### Problem: Raspberry Pi won't boot from SD card

**Symptoms:** No output on screen, no activity LED

**Solution:**
1. Verify SD card is properly flashed:
   ```bash
   # Check image integrity
   sha256sum image.img
   ```

2. Try re-flashing:
   ```bash
   # Unmount SD card partitions first
   sudo umount /dev/sdX*

   # Flash again
   sudo dd if=image.img of=/dev/sdX bs=4M status=progress conv=fsync
   ```

3. Test SD card:
   ```bash
   # Check for bad sectors
   sudo badblocks -v /dev/sdX
   ```

4. Try different SD card (some cards have compatibility issues)

### Problem: Boot stops at "Kernel panic"

**Symptoms:** Boot process fails with kernel panic message

**Solution:**
```bash
# Likely corrupted root filesystem
# Check boot partition
sudo mount /dev/sdX1 /mnt
ls -la /mnt
sudo umount /mnt

# Check root partition
sudo mount /dev/sdX2 /mnt
ls -la /mnt
sudo umount /mnt

# If corrupted, re-flash the image
```

### Problem: Boot is very slow

**Symptoms:** Boot takes 5+ minutes

**Solution:**
1. Check for filesystem errors:
   ```bash
   # From another system with SD card mounted:
   sudo e2fsck -f /dev/sdX2
   ```

2. Disable unnecessary services:
   ```bash
   # On running Pi:
   sudo systemctl disable bluetooth
   sudo systemctl disable hciuart
   ```

3. Check for network timeout issues in boot logs

---

## Display Issues

### Problem: No HDMI output

**Symptoms:** Black screen, monitor shows "No Signal"

**Solution:**
1. Check HDMI cable and connections

2. Force HDMI hotplug:
   ```bash
   # Edit /boot/config.txt or /boot/firmware/config.txt
   hdmi_force_hotplug=1
   hdmi_drive=2
   ```

3. Try different HDMI port on monitor

4. Check GPU memory:
   ```bash
   vcgencmd get_mem gpu
   # Should be at least 128MB, preferably 256MB
   ```

### Problem: Wrong resolution

**Symptoms:** Display is too large/small, wrong aspect ratio

**Solution:**
```bash
# Edit /boot/config.txt
hdmi_group=2    # 1=CEA, 2=DMT
hdmi_mode=82    # 82=1920x1080 60Hz

# Or set specific resolution:
hdmi_cvt=1920 1080 60
hdmi_mode=87

# Reboot to apply
sudo reboot
```

### Problem: Screen blanking even after disabling

**Symptoms:** Screen goes black after inactivity

**Solution:**
```bash
# Check multiple locations:

# 1. X11 settings
cat ~/.config/lxsession/LXDE-pi/autostart
# Should contain:
# @xset s off
# @xset -dpms

# 2. Console blanking
sudo sh -c 'echo "consoleblank=0" >> /boot/cmdline.txt'

# 3. Disable screensaver
xset s off -dpms

# 4. For systemd:
sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
```

### Problem: Wayland instead of X11

**Symptoms:** ofxPiMapper fails with display errors

**Solution:**
```bash
# Check current session type
echo $XDG_SESSION_TYPE

# Should be "x11", not "wayland"

# Force X11:
echo "export GDK_BACKEND=x11" >> ~/.bashrc
echo "export QT_QPA_PLATFORM=xcb" >> ~/.bashrc

# For GDM:
sudo vim /etc/gdm3/custom.conf
# Set: WaylandEnable=false

sudo reboot
```

---

## ofxPiMapper Issues

### Problem: ofxPiMapper won't start

**Symptoms:** Error messages, immediate crash

**Solution:**
1. Check error output:
   ```bash
   cd ~/openFrameworks/addons/ofxPiMapper/example_simpler
   ./bin/example_simpler 2>&1 | tee error.log
   ```

2. Common errors and fixes:

   **"Could not initialize OpenGL"**
   ```bash
   # Check GL drivers
   glxinfo | grep "OpenGL version"

   # Verify KMS driver is loaded
   lsmod | grep vc4
   ```

   **"Permission denied" for /dev/dri**
   ```bash
   # Add user to video group
   sudo usermod -a -G video $USER
   # Logout and login
   ```

   **"Could not open display"**
   ```bash
   export DISPLAY=:0
   xhost +local:
   ```

### Problem: ofxPiMapper runs but shows black screen

**Symptoms:** Application starts but no content visible

**Solution:**
```bash
# 1. Check sources directory
ls -la ~/openFrameworks/addons/ofxPiMapper/example_simpler/bin/data/sources/

# 2. Add test media
cd ~/openFrameworks/addons/ofxPiMapper/example_simpler/bin/data/sources/images/
wget https://via.placeholder.com/1920x1080.png -O test.png

# 3. Check permissions
chmod -R 755 bin/data/

# 4. Try with FBO source example
cd ~/openFrameworks/addons/ofxPiMapper/example_fbo-sources
./bin/example_fbo-sources
```

### Problem: Can't create surfaces

**Symptoms:** Key presses don't create surfaces

**Solution:**
1. Verify you're in correct mode:
   - Press '3' for projection mapping mode
   - Press 't' for triangle, 'q' for quad

2. Check keyboard input:
   ```bash
   # Test keyboard
   xev | grep -i key
   ```

3. Check application focus (click on window)

### Problem: Auto-start doesn't work

**Symptoms:** ofxPiMapper doesn't start on boot

**Solution:**
```bash
# Check status
~/status-ofxpimapper.sh

# Verify systemd service
sudo systemctl status ofxpimapper.service

# Check logs
journalctl -u ofxpimapper.service -n 50

# Verify autostart file
cat ~/.config/autostart/ofxpimapper.desktop

# Try enabling again
~/enable-autostart.sh

# Check delay setting (might need to increase)
# Edit AUTOSTART_DELAY in config
```

---

## Performance Issues

### Problem: Low framerate, choppy playback

**Symptoms:** Laggy interface, stuttering video

**Solution:**
1. Check GPU memory:
   ```bash
   vcgencmd get_mem gpu
   # Increase if below 256MB
   sudo sh -c 'echo "gpu_mem=384" >> /boot/config.txt'
   sudo reboot
   ```

2. Set CPU governor to performance:
   ```bash
   echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
   ```

3. Check temperature:
   ```bash
   vcgencmd measure_temp
   # If > 80°C, add cooling
   ```

4. Reduce complexity:
   - Use fewer surfaces
   - Lower video resolution
   - Reduce grid warp density

### Problem: System overheating

**Symptoms:** Temperature > 85°C, throttling

**Solution:**
1. Check throttling status:
   ```bash
   vcgencmd get_throttled
   # 0x0 = OK, anything else = throttling
   ```

2. Add cooling:
   - Install heatsinks
   - Add fan
   - Improve case ventilation

3. Reduce overclock if enabled

4. Lower GPU memory if excessive

---

## Network Issues

### Problem: WiFi not connecting

**Symptoms:** No network connectivity over WiFi

**Solution:**
```bash
# Check WiFi status
sudo iwconfig

# Scan for networks
sudo iwlist wlan0 scan | grep ESSID

# Check configuration
cat /etc/wpa_supplicant/wpa_supplicant.conf

# Reconfigure WiFi
sudo raspi-config
# Select: System Options -> Wireless LAN

# Or manually:
sudo wpa_passphrase "SSID" "password" | sudo tee -a /etc/wpa_supplicant/wpa_supplicant.conf

# Restart networking
sudo systemctl restart dhcpcd
```

### Problem: Can't SSH to Raspberry Pi

**Symptoms:** Connection refused, timeout

**Solution:**
```bash
# 1. Verify SSH is enabled
sudo systemctl status ssh

# Enable if needed:
sudo systemctl enable ssh
sudo systemctl start ssh

# 2. Check firewall
sudo ufw status
sudo ufw allow 22/tcp

# 3. Find IP address
hostname -I

# 4. Try from client:
ssh -v mapper@<IP_ADDRESS>
```

---

## Audio Issues

### Problem: No audio from video playback

**Symptoms:** Video plays but no sound

**Solution:**
1. Check audio device:
   ```bash
   aplay -l
   ```

2. Set audio output:
   ```bash
   # HDMI audio
   sudo raspi-config
   # System Options -> Audio -> HDMI

   # Or command line:
   amixer cset numid=3 2  # 0=auto, 1=headphones, 2=HDMI
   ```

3. Check volume:
   ```bash
   alsamixer
   # Use arrow keys to increase volume
   ```

4. Verify video has audio:
   ```bash
   ffprobe video.mp4 | grep Audio
   ```

5. Enable audio in ofxPiMapper:
   ```cpp
   // In ofApp.cpp
   ofx::piMapper::VideoSource::enableAudio = true;
   ```

---

## QEMU Testing Issues

### Problem: QEMU won't start

**Symptoms:** Error messages, qemu-system-arm not found

**Solution:**
```bash
# Install QEMU
sudo apt-get install qemu-system-arm qemu-user-static

# Verify installation
which qemu-system-arm
```

### Problem: QEMU kernel download fails

**Symptoms:** Can't download kernel for QEMU

**Solution:**
```bash
# Manual download
cd build-system/testing/qemu-config
wget https://github.com/dhruvvyas90/qemu-rpi-kernel/raw/master/kernel-qemu-5.10.63-buster
wget https://github.com/dhruvvyas90/qemu-rpi-kernel/raw/master/versatile-pb-buster-5.10.63.dtb
```

### Problem: QEMU boots but shows black screen

**Symptoms:** VNC connects but display is black

**Solution:**
1. Wait 2-3 minutes (initial boot is slow)

2. Check console output in terminal

3. Try VNC password if prompted (same as RPI_PASSWORD)

4. Verify VNC port:
   ```bash
   # Try different VNC client
   vncviewer localhost:5900
   ```

---

## Getting Help

If you can't resolve your issue:

1. **Check logs:**
   ```bash
   # System logs
   sudo journalctl -xe

   # ofxPiMapper logs
   cd ~/openFrameworks/addons/ofxPiMapper/example_simpler
   ./bin/example_simpler 2>&1 | tee debug.log
   ```

2. **Collect system information:**
   ```bash
   uname -a
   cat /proc/device-tree/model
   vcgencmd version
   ```

3. **Search existing issues:**
   - [ofxPiMapper Issues](https://github.com/b0rt/ofxPiMapper/issues)
   - [openFrameworks Forum](https://forum.openframeworks.cc/)

4. **Create detailed bug report:**
   - Describe the problem
   - Steps to reproduce
   - Error messages / logs
   - System information
   - Configuration used

5. **Community support:**
   - [ofxPiMapper Gitter](https://gitter.im/kr15h/ofxPiMapper)
   - openFrameworks Discord
   - Raspberry Pi Forums
