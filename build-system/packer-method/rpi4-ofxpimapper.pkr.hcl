// ofxPiMapper Packer Template for Raspberry Pi 4
// This template creates a custom Raspberry Pi OS image with ofxPiMapper pre-installed
// using Packer and QEMU

// Variables
variable "rpi_username" {
  type    = string
  default = "mapper"
}

variable "rpi_password" {
  type    = string
  default = "projection"
}

variable "hostname" {
  type    = string
  default = "ofxpimapper"
}

variable "timezone" {
  type    = string
  default = "UTC"
}

variable "base_image_url" {
  type    = string
  default = "https://downloads.raspberrypi.org/raspios_armhf/images/raspios_armhf-2024-07-04/2024-07-04-raspios-bookworm-armhf.img.xz"
}

variable "of_version" {
  type    = string
  default = "0.12.0"
}

variable "autostart_enabled" {
  type    = bool
  default = false
}

// Locals
locals {
  image_name = "ofxpimapper-rpi4-${formatdate("YYYY-MM-DD", timestamp())}.img"
  build_time = formatdate("YYYY-MM-DD-hhmm", timestamp())
}

// Source: Raspberry Pi ARM Image
source "arm" "raspberry_pi_ofxpimapper" {
  file_urls             = [var.base_image_url]
  file_checksum_type    = "sha256"
  file_checksum_url     = "${var.base_image_url}.sha256"
  file_target_extension = "xz"
  image_build_method    = "resize"
  image_path            = "deploy/${local.image_name}"
  image_size            = "8G"
  image_type            = "dos"

  image_partitions {
    name         = "boot"
    type         = "c"
    start_sector = "8192"
    filesystem   = "vfat"
    size         = "256M"
    mountpoint   = "/boot"
  }

  image_partitions {
    name         = "root"
    type         = "83"
    start_sector = "532480"
    filesystem   = "ext4"
    size         = "0"
    mountpoint   = "/"
  }

  image_chroot_env = [
    "PATH=/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin"
  ]

  qemu_binary_source_path      = "/usr/bin/qemu-arm-static"
  qemu_binary_destination_path = "/usr/bin/qemu-arm-static"
}

// Build
build {
  name = "ofxpimapper"

  sources = ["source.arm.raspberry_pi_ofxpimapper"]

  // Update and upgrade system
  provisioner "shell" {
    inline = [
      "apt-get update",
      "apt-get upgrade -y",
      "apt-get install -y raspi-config"
    ]
  }

  // Set hostname
  provisioner "shell" {
    inline = [
      "echo '${var.hostname}' > /etc/hostname",
      "sed -i 's/127.0.1.1.*/127.0.1.1\\t${var.hostname}/g' /etc/hosts"
    ]
  }

  // Set timezone
  provisioner "shell" {
    inline = [
      "timedatectl set-timezone ${var.timezone} || ln -sf /usr/share/zoneinfo/${var.timezone} /etc/localtime"
    ]
  }

  // Create user
  provisioner "shell" {
    inline = [
      "useradd -m -G adm,dialout,cdrom,sudo,audio,video,plugdev,games,users,input,netdev,gpio,i2c,spi -s /bin/bash ${var.rpi_username}",
      "echo '${var.rpi_username}:${var.rpi_password}' | chpasswd",
      "echo '${var.rpi_username} ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/010_${var.rpi_username}-nopasswd",
      "chmod 0440 /etc/sudoers.d/010_${var.rpi_username}-nopasswd"
    ]
  }

  // Upload and run installation scripts
  provisioner "file" {
    source      = "../scripts/install-dependencies.sh"
    destination = "/tmp/install-dependencies.sh"
  }

  provisioner "shell" {
    inline = [
      "chmod +x /tmp/install-dependencies.sh",
      "bash /tmp/install-dependencies.sh"
    ]
  }

  provisioner "file" {
    source      = "../scripts/configure-x11.sh"
    destination = "/tmp/configure-x11.sh"
  }

  provisioner "shell" {
    inline = [
      "chmod +x /tmp/configure-x11.sh",
      "bash /tmp/configure-x11.sh ${var.rpi_username}"
    ]
  }

  provisioner "file" {
    source      = "../scripts/configure-autologin.sh"
    destination = "/tmp/configure-autologin.sh"
  }

  provisioner "shell" {
    inline = [
      "chmod +x /tmp/configure-autologin.sh",
      "bash /tmp/configure-autologin.sh ${var.rpi_username}"
    ]
  }

  provisioner "file" {
    source      = "../scripts/install-openframeworks.sh"
    destination = "/tmp/install-openframeworks.sh"
  }

  provisioner "shell" {
    inline = [
      "chmod +x /tmp/install-openframeworks.sh",
      "bash /tmp/install-openframeworks.sh ${var.rpi_username}"
    ]
  }

  provisioner "file" {
    source      = "../scripts/install-ofxpimapper.sh"
    destination = "/tmp/install-ofxpimapper.sh"
  }

  provisioner "shell" {
    inline = [
      "chmod +x /tmp/install-ofxpimapper.sh",
      "bash /tmp/install-ofxpimapper.sh ${var.rpi_username}"
    ]
  }

  // Configure auto-start if enabled
  provisioner "file" {
    source      = "../scripts/configure-autostart.sh"
    destination = "/tmp/configure-autostart.sh"
  }

  provisioner "shell" {
    inline = [
      "if [ '${var.autostart_enabled}' = 'true' ]; then chmod +x /tmp/configure-autostart.sh && bash /tmp/configure-autostart.sh ${var.rpi_username}; fi"
    ]
  }

  // Clean up
  provisioner "shell" {
    inline = [
      "apt-get autoremove -y",
      "apt-get autoclean -y",
      "rm -rf /tmp/*",
      "rm -rf /var/lib/apt/lists/*"
    ]
  }

  // Create build info file
  provisioner "shell" {
    inline = [
      "cat > /etc/ofxpimapper-build-info <<EOF",
      "Build Date: ${local.build_time}",
      "Username: ${var.rpi_username}",
      "Hostname: ${var.hostname}",
      "openFrameworks: ${var.of_version}",
      "Auto-start: ${var.autostart_enabled}",
      "EOF"
    ]
  }

  // Post-processing: compress image
  post-processor "compress" {
    output = "deploy/${local.image_name}.zip"
  }

  // Post-processing: generate checksums
  post-processor "checksum" {
    checksum_types = ["sha256"]
    output         = "deploy/${local.image_name}.{{.ChecksumType}}"
  }
}
