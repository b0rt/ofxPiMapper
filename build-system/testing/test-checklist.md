# ofxPiMapper Image Testing Checklist

Use this checklist to verify your custom Raspberry Pi image before deploying to production.

## Pre-Flight Checks

- [ ] Image file exists and is not corrupted
- [ ] Image size is reasonable (3-5 GB)
- [ ] SHA256 checksum matches (if provided)
- [ ] Sufficient SD card size available (8GB+ recommended)

## QEMU Testing

### Boot Test
- [ ] Image boots successfully in QEMU
- [ ] Boot process completes without errors
- [ ] Login prompt appears (console or VNC)
- [ ] Can login with configured username/password

### System Configuration
- [ ] Hostname is correct (`hostname` command)
- [ ] Timezone is correct (`timedatectl` or `date`)
- [ ] Locale is correct (`locale`)
- [ ] Network interfaces are present (`ip addr`)

### Display Configuration (VNC)
- [ ] X11 server starts successfully
- [ ] Desktop environment loads (if using desktop base)
- [ ] Display resolution is appropriate
- [ ] Mouse and keyboard input work
- [ ] No screen blanking during testing

### Software Installation
- [ ] openFrameworks is installed at correct location
  ```bash
  ls -la ~/openFrameworks
  ```
- [ ] openFrameworks core library exists
  ```bash
  ls -la ~/openFrameworks/libs/openFrameworksCompiled/lib/*/libopenFrameworks.a
  ```
- [ ] ofxPiMapper is installed
  ```bash
  ls -la ~/openFrameworks/addons/ofxPiMapper
  ```
- [ ] Required addons are present
  ```bash
  ls -la ~/openFrameworks/addons/ofxOMXPlayer
  ls -la ~/openFrameworks/addons/ofxVideoSync
  ```
- [ ] Example projects are compiled
  ```bash
  ls -la ~/openFrameworks/addons/ofxPiMapper/example_simpler/bin/example_simpler
  ```

### ofxPiMapper Execution
- [ ] Can launch ofxPiMapper manually
  ```bash
  cd ~/openFrameworks/addons/ofxPiMapper/example_simpler
  ./bin/example_simpler
  ```
- [ ] Application starts without errors
- [ ] GUI renders correctly
- [ ] Can create surfaces (press 't' for triangle, 'q' for quad)
- [ ] Can switch modes (1-4 keys)
- [ ] Can exit cleanly (type 'ext')

### Auto-Start Testing (if enabled)
- [ ] Auto-login works on reboot
- [ ] ofxPiMapper starts automatically after login
- [ ] Application launches in fullscreen mode (if configured)
- [ ] Delay before start is appropriate
- [ ] Application restarts on crash (if configured)
- [ ] Can disable auto-start
  ```bash
  ~/disable-autostart.sh
  ```

### Media Playback
- [ ] Sample images are present in `bin/data/sources/images/`
- [ ] Sample videos are present in `bin/data/sources/videos/`
- [ ] Can load image sources
- [ ] Can load video sources
- [ ] Video playback is smooth
- [ ] Audio works (if video has audio)

### Performance
- [ ] GPU memory allocation is correct
  ```bash
  vcgencmd get_mem gpu
  ```
- [ ] CPU governor is set correctly
  ```bash
  cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
  ```
- [ ] No swap usage (if disabled)
  ```bash
  free -h
  ```
- [ ] Temperature is reasonable during operation
  ```bash
  vcgencmd measure_temp
  ```

### Network & Services
- [ ] SSH server is running (if enabled)
  ```bash
  sudo systemctl status ssh
  ```
- [ ] Can connect via SSH
- [ ] VNC server is running (if enabled)
- [ ] WiFi configuration works (if configured)

### Helper Scripts
- [ ] Management scripts are executable
  ```bash
  ls -la ~/*.sh
  ```
- [ ] start-ofxpimapper.sh works
- [ ] stop-ofxpimapper.sh works
- [ ] status-ofxpimapper.sh shows correct status
- [ ] enable/disable-autostart.sh work correctly

## Physical Hardware Testing (After SD Card Flash)

### First Boot
- [ ] Raspberry Pi boots from SD card
- [ ] HDMI output is visible
- [ ] Login prompt appears or auto-login works
- [ ] Network connectivity (WiFi/Ethernet)
- [ ] Can SSH into device

### Hardware Features
- [ ] HDMI audio output works
- [ ] 3.5mm audio output works
- [ ] USB devices are recognized (keyboard, mouse)
- [ ] GPIO access works (if needed)
- [ ] Camera interface works (if using camera examples)

### Graphics Performance
- [ ] OpenGL ES 2.0 is working
  ```bash
  glxinfo | grep "OpenGL version"
  ```
- [ ] Smooth rendering at target resolution
- [ ] No screen tearing
- [ ] Fullscreen mode works correctly

### Projection Mapping
- [ ] Can map surfaces to physical projection
- [ ] Perspective warping works correctly
- [ ] Multiple surfaces can be created
- [ ] Can save and load compositions (press 's' to save)
- [ ] Compositions persist after reboot

### Stress Testing
- [ ] System stable under continuous operation (2+ hours)
- [ ] Temperature remains in safe range (<85°C)
- [ ] No memory leaks during extended use
- [ ] Auto-restart works after crash/hang

### Production Readiness
- [ ] All default passwords changed
- [ ] Unnecessary services disabled
- [ ] Firewall configured (if needed)
- [ ] Remote access secured
- [ ] Backup/recovery plan in place

## Documentation Verification

- [ ] README is clear and complete
- [ ] All configuration options documented
- [ ] Troubleshooting guide is helpful
- [ ] Known issues are listed
- [ ] Example media/projects are provided

## Final Sign-Off

**Tested by:** ___________________________

**Date:** ___________________________

**Image version:** ___________________________

**Hardware tested:** ___________________________

**Notes:**
```
[Add any additional notes, issues, or observations here]
```

**Ready for production:** [ ] Yes  [ ] No

**If No, list blocking issues:**
1.
2.
3.
