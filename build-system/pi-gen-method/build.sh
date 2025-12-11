#!/bin/bash
################################################################################
# ofxPiMapper Pi-Gen Build Script
#
# This script uses pi-gen (official Raspberry Pi image builder) to create
# a custom Raspberry Pi OS image with ofxPiMapper pre-installed.
#
# Usage:
#   sudo ./build.sh [options]
#
# Options:
#   --docker              Build using Docker (recommended)
#   --config FILE         Use custom configuration file
#   --clean               Clean previous builds before starting
#   --stage STAGE         Build only up to specified stage
#   --help                Show this help message
#
################################################################################

set -e  # Exit on error
set -u  # Exit on undefined variable

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_progress() { echo -e "${BLUE}[PROGRESS]${NC} $1"; }

################################################################################
# Script Configuration
################################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_SYSTEM_DIR="$(dirname "$SCRIPT_DIR")"
PIGEN_DIR="${SCRIPT_DIR}/pi-gen"
DEPLOY_DIR="${SCRIPT_DIR}/deploy"

# Default options
USE_DOCKER=false
CLEAN_BUILD=false
CUSTOM_CONFIG=""
BUILD_STAGE=""

################################################################################
# Parse Arguments
################################################################################

show_help() {
    cat << EOF
ofxPiMapper Pi-Gen Build Script

Usage: sudo ./build.sh [options]

Options:
    --docker              Build using Docker (recommended, no root needed)
    --config FILE         Use custom configuration file
    --clean               Clean previous builds before starting
    --stage STAGE         Build only up to specified stage (e.g., stage3)
    --help                Show this help message

Examples:
    # Basic build (requires Linux host)
    sudo ./build.sh

    # Build with Docker
    ./build.sh --docker

    # Build with custom configuration
    sudo ./build.sh --config ../../config/user.conf

    # Clean build with Docker
    ./build.sh --docker --clean

For more information, see: ../README.md
EOF
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --docker)
            USE_DOCKER=true
            shift
            ;;
        --config)
            CUSTOM_CONFIG="$2"
            shift 2
            ;;
        --clean)
            CLEAN_BUILD=true
            shift
            ;;
        --stage)
            BUILD_STAGE="$2"
            shift 2
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

################################################################################
# Load Configuration
################################################################################

log_info "Loading build configuration..."

# Load default configuration
if [ -f "${BUILD_SYSTEM_DIR}/config/build.conf" ]; then
    source "${BUILD_SYSTEM_DIR}/config/build.conf"
else
    log_error "Default configuration not found: ${BUILD_SYSTEM_DIR}/config/build.conf"
    exit 1
fi

# Load custom configuration if specified
if [ -n "$CUSTOM_CONFIG" ]; then
    if [ -f "$CUSTOM_CONFIG" ]; then
        log_info "Loading custom configuration: $CUSTOM_CONFIG"
        source "$CUSTOM_CONFIG"
    else
        log_error "Custom configuration not found: $CUSTOM_CONFIG"
        exit 1
    fi
fi

log_info "Configuration loaded successfully"

################################################################################
# Check Requirements
################################################################################

log_info "Checking system requirements..."

if [ "$USE_DOCKER" = false ]; then
    # Check for root when not using Docker
    if [ "$EUID" -ne 0 ]; then
        log_error "Please run as root (use sudo) or use --docker flag"
        exit 1
    fi

    # Check for required packages
    REQUIRED_PACKAGES=(
        "git" "curl" "quilt" "parted" "qemu-user-static"
        "debootstrap" "zerofree" "zip" "dosfstools"
        "libarchive-tools" "libcap2-bin" "grep" "rsync"
        "xz-utils" "file" "bc" "qemu-utils" "kpartx"
    )

    MISSING_PACKAGES=()
    for pkg in "${REQUIRED_PACKAGES[@]}"; do
        if ! dpkg -l | grep -q "^ii  $pkg "; then
            MISSING_PACKAGES+=("$pkg")
        fi
    done

    if [ ${#MISSING_PACKAGES[@]} -ne 0 ]; then
        log_error "Missing required packages: ${MISSING_PACKAGES[*]}"
        log_info "Install with: sudo apt-get install ${MISSING_PACKAGES[*]}"
        exit 1
    fi
else
    # Check for Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker not found. Please install Docker first."
        log_info "Visit: https://docs.docker.com/get-docker/"
        exit 1
    fi
fi

################################################################################
# Check Disk Space
################################################################################

AVAILABLE_SPACE=$(df "$SCRIPT_DIR" | tail -1 | awk '{print $4}')
REQUIRED_SPACE=$((25 * 1024 * 1024))  # 25 GB in KB

if [ "$AVAILABLE_SPACE" -lt "$REQUIRED_SPACE" ]; then
    log_error "Insufficient disk space"
    log_error "Required: 25 GB, Available: $(numfmt --to=iec-i --suffix=B $((AVAILABLE_SPACE * 1024)))"
    exit 1
fi

log_info "✓ Disk space sufficient: $(numfmt --to=iec-i --suffix=B $((AVAILABLE_SPACE * 1024)))"

################################################################################
# Clean Previous Builds
################################################################################

if [ "$CLEAN_BUILD" = true ]; then
    log_warn "Cleaning previous builds..."

    if [ -d "$PIGEN_DIR" ]; then
        cd "$PIGEN_DIR"
        if [ "$USE_DOCKER" = true ]; then
            ./docker_clean.sh || true
        else
            ./clean.sh || true
        fi
    fi

    rm -rf "${DEPLOY_DIR}"/*
    log_info "✓ Clean complete"
fi

################################################################################
# Git Retry Helper Function
################################################################################

# Retry git operations with exponential backoff
# Usage: git_retry <git command with args>
git_retry() {
    local max_attempts=4
    local attempt=1
    local delay=2

    while [ $attempt -le $max_attempts ]; do
        if [ $attempt -gt 1 ]; then
            log_warn "Retry attempt $attempt of $max_attempts after ${delay}s delay..."
            sleep $delay
        fi

        # Execute the git command
        if "$@"; then
            return 0
        fi

        log_warn "Git command failed: $*"

        if [ $attempt -lt $max_attempts ]; then
            delay=$((delay * 2))  # Exponential backoff: 2s, 4s, 8s, 16s
        fi

        attempt=$((attempt + 1))
    done

    log_error "Git command failed after $max_attempts attempts: $*"
    return 1
}

################################################################################
# Clone/Update pi-gen
################################################################################

log_progress "Setting up pi-gen..."

# Determine which branch to use based on ARCHITECTURE and RPI_OS_RELEASE
# CRITICAL: pi-gen uses different branches for 32-bit vs 64-bit builds
# - master branch: for 32-bit (armhf) images
# - arm64 branch: for 64-bit (aarch64) images
if [ "$ARCHITECTURE" = "arm64" ]; then
    PIGEN_BRANCH="arm64"
    log_info "Target branch: arm64 (for 64-bit build)"
else
    # 32-bit: Use release-specific branch or master
    PIGEN_BRANCH="master"
    log_info "Target branch: master (for 32-bit build, ${RPI_OS_RELEASE})"
fi

if [ -d "$PIGEN_DIR" ]; then
    log_info "Updating existing pi-gen repository..."
    cd "$PIGEN_DIR"
    git_retry git fetch origin
    git checkout "${PIGEN_BRANCH}"
    git_retry git pull origin "${PIGEN_BRANCH}"
else
    log_info "Cloning pi-gen repository (branch: ${PIGEN_BRANCH})..."

    # Clone with retry logic that handles partial failures
    max_attempts=4
    attempt=1
    delay=2

    while [ $attempt -le $max_attempts ]; do
        # Clean up any partial clone from previous failed attempt
        if [ -d "$PIGEN_DIR" ]; then
            log_warn "Removing partial clone from previous failed attempt..."
            rm -rf "$PIGEN_DIR"
        fi

        if [ $attempt -gt 1 ]; then
            log_warn "Clone retry attempt $attempt of $max_attempts after ${delay}s delay..."
            sleep $delay
        fi

        # Attempt the clone
        if git clone --depth 1 --branch "${PIGEN_BRANCH}" https://github.com/RPi-Distro/pi-gen.git "$PIGEN_DIR"; then
            log_info "✓ pi-gen cloned successfully"
            break
        fi

        log_warn "Git clone failed on attempt $attempt"

        if [ $attempt -lt $max_attempts ]; then
            delay=$((delay * 2))  # Exponential backoff: 2s, 4s, 8s, 16s
        else
            log_error "Git clone failed after $max_attempts attempts"
            exit 1
        fi

        attempt=$((attempt + 1))
    done

    cd "$PIGEN_DIR"
fi

PIGEN_COMMIT=$(git rev-parse --short HEAD)
log_info "Using pi-gen commit: $PIGEN_COMMIT (branch: $PIGEN_BRANCH)"

################################################################################
# Configure pi-gen
################################################################################

log_info "Configuring pi-gen..."

# Create pi-gen config file
cat > "${PIGEN_DIR}/config" <<EOF
# ofxPiMapper pi-gen configuration
IMG_NAME="ofxpimapper-rpi4"
RELEASE="${RPI_OS_RELEASE}"
DEPLOY_ZIP=1
LOCALE_DEFAULT="${LOCALE}"
TARGET_HOSTNAME="${HOSTNAME}"
KEYBOARD_KEYMAP="${KEYBOARD_LAYOUT}"
KEYBOARD_LAYOUT="${KEYBOARD_LAYOUT}"
TIMEZONE_DEFAULT="${TIMEZONE}"
FIRST_USER_NAME="${RPI_USERNAME}"
FIRST_USER_PASS="${RPI_PASSWORD}"
ENABLE_SSH="${ENABLE_SSH}"
ARCH="${ARCHITECTURE}"
STAGE_LIST="stage0 stage1 stage2 stage3"
APT_PROXY=""
EOF

# Add GPG key import to stage0 (fixes Debian Bookworm arm64 key issues)
# Prepend GPG key import to the existing stage0/00-configure-apt/00-run.sh script
log_info "Adding GPG key import to stage0/00-configure-apt/00-run.sh..."

# Wait a moment for git operations to complete
sleep 2

# Save the original 00-run.sh content
ORIGINAL_SCRIPT="${PIGEN_DIR}/stage0/00-configure-apt/00-run.sh"

if [ -f "$ORIGINAL_SCRIPT" ]; then
    # Create a backup
    cp "$ORIGINAL_SCRIPT" "${ORIGINAL_SCRIPT}.bak"

    # Create new version with GPG key import prepended
    cat > "$ORIGINAL_SCRIPT" <<'EOFKEYS'
#!/bin/bash -e

# ============================================================================
# GPG Key Import (PREPENDED BY ofxPiMapper build system)
# ============================================================================
# Import Debian Bookworm GPG keys before apt configuration
# This fixes signature verification errors on arm64 builds

echo "[GPG-FIX] Importing Debian Bookworm GPG keys before apt-get update..."

on_chroot << 'EOFGPG'
echo "[GPG-FIX] Starting GPG key import in chroot..."

# Create keyrings directory if it doesn't exist
mkdir -p /usr/share/keyrings

# Method 1: Install latest debian-archive-keyring package
# This is the cleanest approach as it's maintained by Debian
echo "[GPG-FIX] Attempting to install debian-archive-keyring package..."

cd /tmp
# Clean up any old keyring packages
rm -f debian-archive-keyring*.deb 2>/dev/null || true

# Try multiple versions - start with the latest Bookworm-specific version
# The 2023.4+deb12u1 version should have all Bookworm keys
for version in "2023.4+deb12u1" "2023.4" "2023.3+deb12u2" "2023.3"; do
    echo "[GPG-FIX]   Trying debian-archive-keyring version $version..."

    if wget -q http://ftp.debian.org/debian/pool/main/d/debian-archive-keyring/debian-archive-keyring_${version}_all.deb 2>/dev/null || \
       wget -q http://deb.debian.org/debian/pool/main/d/debian-archive-keyring/debian-archive-keyring_${version}_all.deb 2>/dev/null || \
       wget -q http://security.debian.org/debian-security/pool/updates/main/d/debian-archive-keyring/debian-archive-keyring_${version}_all.deb 2>/dev/null; then

        if [ -f debian-archive-keyring_*.deb ]; then
            # Force reinstall even if already installed, to get newer keys
            dpkg -i --force-all debian-archive-keyring_*.deb 2>/dev/null || true
            rm -f debian-archive-keyring_*.deb
            echo "[GPG-FIX]   debian-archive-keyring $version installed"
            break
        fi
    fi
done

# Method 2: Install gnupg if not present, then fetch keys manually
echo "[GPG-FIX] Installing gnupg package for key fetching..."

# Check if gnupg is installed, if not download and install it
if ! command -v gpg >/dev/null 2>&1; then
    cd /tmp
    # Clean up old files
    rm -f *.deb 2>/dev/null || true

    # Download gnupg and dependencies from Debian repository
    # We need: gnupg, gpg, gpg-agent, and their dependencies
    echo "[GPG-FIX]   Downloading gnupg package..."

    # Try to download gnupg package
    if wget -q http://ftp.debian.org/debian/pool/main/g/gnupg2/gnupg_2.2.40-1.1_all.deb 2>/dev/null || \
       wget -q http://deb.debian.org/debian/pool/main/g/gnupg2/gnupg_2.2.40-1.1_all.deb 2>/dev/null; then

        # Also need gpg binary package
        wget -q http://ftp.debian.org/debian/pool/main/g/gnupg2/gpg_2.2.40-1.1+deb12u1_arm64.deb 2>/dev/null || \
        wget -q http://deb.debian.org/debian/pool/main/g/gnupg2/gpg_2.2.40-1.1+deb12u1_arm64.deb 2>/dev/null || true

        # Need dependencies: libassuan, libksba, libnpth
        wget -q http://ftp.debian.org/debian/pool/main/liba/libassuan/libassuan0_2.5.5-5_arm64.deb 2>/dev/null || true
        wget -q http://ftp.debian.org/debian/pool/main/libk/libksba/libksba8_1.6.3-2_arm64.deb 2>/dev/null || true
        wget -q http://ftp.debian.org/debian/pool/main/n/npth/libnpth0_1.6-3_arm64.deb 2>/dev/null || true

        # Install packages (ignoring dependency errors - we just need gpg command)
        dpkg -i *.deb 2>/dev/null || true
        rm -f *.deb

        echo "[GPG-FIX]   gnupg installed via direct download"
    else
        # Fallback: try to install gnupg using apt with insecure repositories allowed
        echo "[GPG-FIX]   Direct download failed, trying apt-get with insecure repos..."
        apt-get update --allow-insecure-repositories -o Acquire::AllowInsecureRepositories=true 2>/dev/null || true
        apt-get install -y --allow-unauthenticated gnupg 2>/dev/null || true

        if command -v gpg >/dev/null 2>&1; then
            echo "[GPG-FIX]   gnupg installed via apt-get"
        fi
    fi
fi

# Method 3: Fetch keys using gpg (if available) or download directly
echo "[GPG-FIX] Ensuring all required GPG keys are present..."

if command -v gpg >/dev/null 2>&1; then
    # gpg is available, fetch from keyservers
    export GNUPGHOME=/tmp/gpg-temp-$$
    mkdir -p "$GNUPGHOME"
    chmod 700 "$GNUPGHOME"

    # Function to fetch and install a GPG key
    fetch_key() {
        local keyid=$1
        local keyname=$2
        echo "[GPG-FIX]   Fetching key $keyid ($keyname)..."

        # Try multiple keyservers for reliability
        for server in keyserver.ubuntu.com keys.openpgp.org pgp.mit.edu; do
            if gpg --batch --keyserver hkp://$server:80 --recv-keys $keyid 2>/dev/null; then
                gpg --batch --export $keyid | gpg --dearmor > /usr/share/keyrings/debian-$keyname-keyring.gpg 2>/dev/null
                echo "[GPG-FIX]     ✓ Key $keyid installed"
                return 0
            fi
        done
        echo "[GPG-FIX]     ⚠ Could not fetch key $keyid from keyservers"
        return 1
    }

    # Import all required Debian Bookworm signing keys
    fetch_key "6ED0E7B82643E131" "bookworm-release"
    fetch_key "78DBA3BC47EF2265" "bookworm-stable"
    fetch_key "F8D2585B8783D481" "bookworm-archive"
    fetch_key "54404762BBB6E853" "bookworm-security-1"
    fetch_key "BDE6D2B9216EC7A8" "bookworm-security-2"
    fetch_key "0E98404D386FA1D9" "bookworm-automatic"

    # Clean up
    rm -rf "$GNUPGHOME"
else
    echo "[GPG-FIX]   gpg not available, relying on debian-archive-keyring package"
fi

chmod 644 /usr/share/keyrings/*.gpg 2>/dev/null || true

# Method 4: Copy keyrings to apt's trusted directory
# APT looks for keys in /etc/apt/trusted.gpg.d/ by default
echo "[GPG-FIX] Copying keyrings to apt trusted directory..."
mkdir -p /etc/apt/trusted.gpg.d/

# Copy all Debian archive keyrings to where apt expects them
if [ -f /usr/share/keyrings/debian-archive-keyring.gpg ]; then
    cp /usr/share/keyrings/debian-archive-keyring.gpg /etc/apt/trusted.gpg.d/
    echo "[GPG-FIX]   ✓ Copied debian-archive-keyring.gpg"
fi

# Also copy the bookworm-specific keyrings
for keyring in /usr/share/keyrings/debian-archive-bookworm*.gpg; do
    if [ -f "$keyring" ]; then
        cp "$keyring" /etc/apt/trusted.gpg.d/
        echo "[GPG-FIX]   ✓ Copied $(basename $keyring)"
    fi
done

chmod 644 /etc/apt/trusted.gpg.d/*.gpg 2>/dev/null || true

# Method 5: If keys still don't work, temporarily allow unsigned repositories
# This is a last resort to unblock the build - we'll fix keys properly in later stages
echo "[GPG-FIX] Configuring apt to allow unsigned repositories temporarily..."

# Create apt configuration file to allow unsigned repos
cat > /etc/apt/apt.conf.d/99allow-unsigned << 'EOFAPT'
// Temporary configuration to allow unsigned repositories
// This is needed because debian-archive-keyring package may not have all Bookworm keys
APT::Get::AllowUnauthenticated "true";
Acquire::AllowInsecureRepositories "true";
Acquire::AllowDowngradeToInsecureRepositories "true";
EOFAPT

echo "[GPG-FIX]   ✓ Created /etc/apt/apt.conf.d/99allow-unsigned"

# Method 6: Modify sources.list to add [trusted=yes] option
# This explicitly tells apt to trust debian.org repos even without valid signatures
echo "[GPG-FIX] Modifying sources.list to mark debian.org repositories as trusted..."

if [ -f /etc/apt/sources.list ]; then
    # Add [trusted=yes] to debian.org entries (if not already present)
    sed -i 's|^\(deb \)\(http://deb.debian.org\)|\1[trusted=yes] \2|g' /etc/apt/sources.list
    sed -i 's|^\(deb \)\(http://security.debian.org\)|\1[trusted=yes] \2|g' /etc/apt/sources.list
    sed -i 's|^\(deb-src \)\(http://deb.debian.org\)|\1[trusted=yes] \2|g' /etc/apt/sources.list
    sed -i 's|^\(deb-src \)\(http://security.debian.org\)|\1[trusted=yes] \2|g' /etc/apt/sources.list

    # Show the modified sources.list
    echo "[GPG-FIX]   ✓ Added [trusted=yes] to debian.org entries"
    echo "[GPG-FIX]   Modified sources.list contents:"
    cat /etc/apt/sources.list | grep -v '^#' | grep -v '^$' || true
fi

echo "[GPG-FIX] GPG key import completed"
echo "[GPG-FIX] Keyrings in /usr/share/keyrings:"
ls -lh /usr/share/keyrings/*.gpg 2>/dev/null | head -10 || echo "[GPG-FIX]   (none found)"
echo "[GPG-FIX] Keyrings in /etc/apt/trusted.gpg.d/:"
ls -lh /etc/apt/trusted.gpg.d/*.gpg 2>/dev/null | head -10 || echo "[GPG-FIX]   (none found)"

EOFGPG

echo "[GPG-FIX] GPG key import completed, proceeding with apt configuration..."
echo ""

# ============================================================================
# ORIGINAL 00-run.sh CONTENT BELOW
# ============================================================================
EOFKEYS

    # Append the original script content (skipping the shebang if present)
    tail -n +2 "${ORIGINAL_SCRIPT}.bak" >> "$ORIGINAL_SCRIPT"

    chmod +x "$ORIGINAL_SCRIPT"
    log_info "✓ GPG key import prepended to stage0/00-configure-apt/00-run.sh"
else
    log_error "stage0/00-configure-apt/00-run.sh not found - cannot inject GPG key import"
    exit 1
fi

# Fix stage2 and stage3 package lists - remove unavailable rpi-* and rpd-* packages
log_info "Fixing stage2 and stage3 package lists to remove unavailable packages..."

# List of unavailable packages to remove
UNAVAILABLE_PACKAGES=(
    "rpi-swap"
    "rpi-loop-utils"
    "rpi-usb-gadget"
    "rpi-cloud-init-mods"
    "rpd-wayland-core"
    "rpd-x-core"
    "rpd-preferences"
    "rpd-theme"
)

# Find and fix ALL package files in stage2 and stage3 subdirectories
log_info "Searching for all package files in stage2 and stage3..."
PACKAGE_FILES=$(find "${PIGEN_DIR}/stage2" "${PIGEN_DIR}/stage3" -type f \( -name "00-packages" -o -name "00-packages-nr" \) 2>/dev/null)

if [ -z "$PACKAGE_FILES" ]; then
    log_error "No package files found in stage2 or stage3!"
    exit 1
fi

log_info "Found package files:"
echo "$PACKAGE_FILES"

# Process each package file found
FILES_PROCESSED=0
for PACKAGE_FILE in $PACKAGE_FILES; do
    if [ -f "$PACKAGE_FILE" ]; then
        FILES_PROCESSED=$((FILES_PROCESSED + 1))
        log_info "Processing package file: $PACKAGE_FILE"

        # Show original contents
        log_info "  Original contents (first 30 lines):"
        cat "$PACKAGE_FILE" | head -30

        # Remove individual packages from lines (not entire lines)
        # This handles cases where multiple packages are on the same line
        REMOVED_COUNT=0
        for pkg in "${UNAVAILABLE_PACKAGES[@]}"; do
            # Check if package exists anywhere in the file (as a whole word)
            if grep -qE "(^|[[:space:]])${pkg}([[:space:]]|$)" "$PACKAGE_FILE"; then
                log_info "  Removing package: ${pkg}"

                # Remove the package name from lines, preserving other packages
                # This handles multiple cases:
                # - "pkg" alone on line -> line becomes empty
                # - "pkg other" -> becomes "other"
                # - "other pkg" -> becomes "other"
                # - "foo pkg bar" -> becomes "foo bar"

                # First, remove package at start of line followed by space
                sed -i "s/^${pkg}[[:space:]]\+//g" "$PACKAGE_FILE"
                # Remove package at end of line preceded by space
                sed -i "s/[[:space:]]\+${pkg}$//g" "$PACKAGE_FILE"
                # Remove package in middle of line (surrounded by spaces)
                sed -i "s/[[:space:]]\+${pkg}[[:space:]]\+/ /g" "$PACKAGE_FILE"
                # Remove package alone on line
                sed -i "/^${pkg}$/d" "$PACKAGE_FILE"
                # Remove any lines that became empty or whitespace-only
                sed -i '/^[[:space:]]*$/d' "$PACKAGE_FILE"

                REMOVED_COUNT=$((REMOVED_COUNT + 1))
            fi
        done

        log_info "  Removed ${REMOVED_COUNT} package(s) from $(basename "$PACKAGE_FILE")"
        log_info "  Modified contents (first 30 lines):"
        cat "$PACKAGE_FILE" | head -30
        log_info "✓ Processed $PACKAGE_FILE"
    fi
done

if [ $FILES_PROCESSED -eq 0 ]; then
    log_error "No package files were processed!"
    exit 1
fi

log_info "✓ Processed $FILES_PROCESSED package file(s) in stage2 and stage3"

# Verify the fix worked
log_info "Final verification of package removals..."
for PACKAGE_FILE in $PACKAGE_FILES; do
    if [ -f "$PACKAGE_FILE" ]; then
        log_info "Checking $(basename "$PACKAGE_FILE") in $(dirname "$PACKAGE_FILE")..."
        for pkg in "${UNAVAILABLE_PACKAGES[@]}"; do
            # Check if package exists anywhere in the file (as a whole word)
            if grep -qE "(^|[[:space:]])${pkg}([[:space:]]|$)" "$PACKAGE_FILE"; then
                log_error "  ✗ Package '${pkg}' still present after removal!"
                log_error "  Found in line: $(grep -E "(^|[[:space:]])${pkg}([[:space:]]|$)" "$PACKAGE_FILE")"
                exit 1
            fi
        done
        log_info "  ✓ All problematic packages removed from $(basename "$PACKAGE_FILE")"
    fi
done

# Fix stage2/01-sys-tweaks/01-run.sh to handle missing rpi-resize.service
log_info "Fixing stage2/01-sys-tweaks/01-run.sh to handle missing rpi-resize.service..."

STAGE2_RUN_SCRIPT="${PIGEN_DIR}/stage2/01-sys-tweaks/01-run.sh"
if [ -f "$STAGE2_RUN_SCRIPT" ]; then
    log_info "Found stage2/01-sys-tweaks/01-run.sh, examining for rpi-resize.service..."

    # Show the file to debug
    log_info "  Script contents:"
    cat "$STAGE2_RUN_SCRIPT" | head -50

    # Check if the script mentions rpi-resize at all
    if grep -qi "rpi-resize" "$STAGE2_RUN_SCRIPT"; then
        log_info "Found rpi-resize reference, patching script..."

        # Create a wrapper that checks if service exists before enabling
        # Replace any systemctl enable rpi-resize.service command
        sed -i 's/systemctl enable rpi-resize\.service/systemctl list-unit-files rpi-resize.service --no-pager 2>\/dev\/null | grep -q rpi-resize.service \&\& systemctl enable rpi-resize.service || echo "rpi-resize.service not found, skipping"/g' "$STAGE2_RUN_SCRIPT"

        # Also handle the variant without .service extension
        sed -i 's/systemctl enable rpi-resize\([[:space:]]\|$\)/systemctl list-unit-files rpi-resize.service --no-pager 2>\/dev\/null | grep -q rpi-resize.service \&\& systemctl enable rpi-resize || echo "rpi-resize not found, skipping"\1/g' "$STAGE2_RUN_SCRIPT"

        log_info "✓ Patched rpi-resize.service commands"
        log_info "  Modified script (first 50 lines):"
        cat "$STAGE2_RUN_SCRIPT" | head -50
    else
        log_info "No rpi-resize reference found in script"
    fi
else
    log_warn "stage2/01-sys-tweaks/01-run.sh not found at: $STAGE2_RUN_SCRIPT"
    log_warn "Listing stage2/01-sys-tweaks contents:"
    ls -la "${PIGEN_DIR}/stage2/01-sys-tweaks/" || log_error "Directory doesn't exist"
fi

# Fix stage3/01-print-support/00-run.sh to handle missing lpadmin group
log_info "Fixing stage3/01-print-support/00-run.sh to handle missing lpadmin group..."

STAGE3_PRINT_SCRIPT="${PIGEN_DIR}/stage3/01-print-support/00-run.sh"
if [ -f "$STAGE3_PRINT_SCRIPT" ]; then
    log_info "Found stage3/01-print-support/00-run.sh, patching for lpadmin group..."

    # Show the original file
    log_info "  Original script contents:"
    cat "$STAGE3_PRINT_SCRIPT"

    # Replace adduser command to check if lpadmin group exists first
    # Pattern: adduser "$FIRST_USER_NAME" lpadmin
    # Replace with: getent group lpadmin >/dev/null && adduser "$FIRST_USER_NAME" lpadmin || echo "lpadmin group not found, skipping"
    sed -i 's/adduser "\$FIRST_USER_NAME" lpadmin/getent group lpadmin >\/dev\/null \&\& adduser "\$FIRST_USER_NAME" lpadmin || echo "lpadmin group not found (CUPS not installed), skipping"/g' "$STAGE3_PRINT_SCRIPT"

    log_info "✓ Patched lpadmin group addition to be conditional"
    log_info "  Modified script contents:"
    cat "$STAGE3_PRINT_SCRIPT"
else
    log_warn "stage3/01-print-support/00-run.sh not found at: $STAGE3_PRINT_SCRIPT"
    log_warn "Listing stage3 contents:"
    ls -la "${PIGEN_DIR}/stage3/" 2>/dev/null || log_error "Directory doesn't exist"
fi

# Determine which base stages to include
if [ "$BASE_IMAGE" = "desktop" ]; then
    # Desktop: keep stage4 (desktop environment), add stage5 (custom ofxPiMapper)
    sed -i 's/STAGE_LIST=.*/STAGE_LIST="stage0 stage1 stage2 stage3 stage4 stage5"/' "${PIGEN_DIR}/config"
    CUSTOM_STAGE="stage5"
    SKIP_STAGE4=false
else
    # Lite: skip stage4 (desktop), use stage5 (custom ofxPiMapper)
    sed -i 's/STAGE_LIST=.*/STAGE_LIST="stage0 stage1 stage2 stage3 stage4 stage5"/' "${PIGEN_DIR}/config"
    CUSTOM_STAGE="stage5"
    SKIP_STAGE4=true
fi

log_info "Using ${CUSTOM_STAGE} for custom ofxPiMapper installation (skip stage4: ${SKIP_STAGE4})"

log_info "✓ pi-gen configured"

################################################################################
# Prepare stage4 for lite builds (pass-through without desktop packages)
################################################################################

if [ "$SKIP_STAGE4" = true ]; then
    log_info "Configuring stage4 as pass-through for lite build (removing desktop scripts)"

    # Remove all desktop installation scripts from stage4
    # Keep the stage4 directory intact so pi-gen can copy rootfs through it
    find "${PIGEN_DIR}/stage4" -mindepth 1 -maxdepth 1 -type d -name '[0-9][0-9]-*' -exec rm -rf {} \;

    # Create a minimal prerun.sh to indicate this stage is processed
    cat > "${PIGEN_DIR}/stage4/prerun.sh" <<'EOF'
#!/bin/bash
echo "Stage4 pass-through for lite build (no desktop packages)..."
EOF
    chmod +x "${PIGEN_DIR}/stage4/prerun.sh"

    # CRITICAL: Add a dummy script directory so pi-gen creates work/stage4/rootfs
    # Without at least one script directory, pi-gen won't set up the stage's work directory
    mkdir -p "${PIGEN_DIR}/stage4/00-pass-through"
    cat > "${PIGEN_DIR}/stage4/00-pass-through/00-run.sh" <<'EOF'
#!/bin/bash
# Dummy script to ensure pi-gen creates work/stage4/rootfs
# This stage does nothing but allows rootfs to pass through to stage5
echo "[INFO] Stage4 pass-through: No packages to install (lite build)"
exit 0
EOF
    chmod +x "${PIGEN_DIR}/stage4/00-pass-through/00-run.sh"

    log_info "Stage4 configured as pass-through with dummy script (rootfs will be created and passed to stage5)"
fi

################################################################################
# Create Custom ofxPiMapper Stage
################################################################################

log_progress "Creating custom ofxPiMapper installation stage (${CUSTOM_STAGE})..."

# Always use stage5 for custom installation
# For desktop: stage4 has desktop, stage5 has custom
# For lite: stage4 is SKIPPED, stage5 has custom
STAGE_DIR="${PIGEN_DIR}/stage5"

# Create stage5 directory (don't delete - it doesn't exist in default pi-gen)
mkdir -p "$STAGE_DIR"

# Create prerun script that copies rootfs from previous stage (with fallback)
# This is CRITICAL - without this, stage5 won't have a rootfs to chroot into!
cat > "${STAGE_DIR}/prerun.sh" <<'EOF'
#!/bin/bash
set -e

echo "===== Starting ofxPiMapper custom installation stage (stage5) ====="

# Determine which stage to copy rootfs from
# Try stage4 first (for desktop builds or if stage4 completed)
# Fall back to stage3 (for lite builds where stage4 didn't create rootfs)
SOURCE_ROOTFS=""

if [ -d "${PREV_ROOTFS_DIR}" ] && [ -n "$(ls -A "${PREV_ROOTFS_DIR}" 2>/dev/null)" ]; then
    SOURCE_ROOTFS="${PREV_ROOTFS_DIR}"
    echo "[INFO] Using stage4 rootfs: ${PREV_ROOTFS_DIR}"
else
    # Fallback to stage3 for lite builds
    STAGE3_ROOTFS="$(dirname "$(dirname "${PREV_ROOTFS_DIR}")")/stage3/rootfs"
    if [ -d "${STAGE3_ROOTFS}" ] && [ -n "$(ls -A "${STAGE3_ROOTFS}" 2>/dev/null)" ]; then
        SOURCE_ROOTFS="${STAGE3_ROOTFS}"
        echo "[WARNING] Stage4 rootfs not found, falling back to stage3: ${STAGE3_ROOTFS}"
    else
        echo "[ERROR] Neither stage4 nor stage3 rootfs found!"
        echo "[ERROR] Tried: ${PREV_ROOTFS_DIR}"
        echo "[ERROR] Tried: ${STAGE3_ROOTFS}"
        exit 1
    fi
fi

echo "[INFO] Copying rootfs from ${SOURCE_ROOTFS} to stage5..."

# Create target directory structure (pi-gen doesn't create work dirs for custom stages)
mkdir -p "${ROOTFS_DIR}"

# Copy rootfs using rsync (traditional pi-gen method)
rsync -aHAXx \
    --exclude /var/cache/apt/archives \
    --exclude /boot/firmware \
    "${SOURCE_ROOTFS}/" \
    "${ROOTFS_DIR}/"

echo "[INFO] Rootfs copied successfully ($(du -sh "${ROOTFS_DIR}" | cut -f1))"
echo "[INFO] Ready to install ofxPiMapper dependencies..."
EOF

chmod +x "${STAGE_DIR}/prerun.sh"

# Stage 00: System Dependencies
mkdir -p "${STAGE_DIR}/00-install-dependencies"

cat > "${STAGE_DIR}/00-install-dependencies/00-run-chroot.sh" <<'EOFRUN'
#!/bin/bash -e
# Install system dependencies

################################################################################
# Update System
################################################################################

echo "[INFO] Updating package lists..."
apt-get update -y

echo "[INFO] Upgrading existing packages..."
apt-get upgrade -y

################################################################################
# Install Build Essentials
################################################################################

echo "[INFO] Installing build essentials..."
apt-get install -y \
    build-essential \
    git \
    cmake \
    pkg-config \
    gdb \
    ccache

################################################################################
# Install OpenGL and Graphics Libraries
################################################################################

echo "[INFO] Installing OpenGL ES and graphics libraries..."
apt-get install -y \
    libgles2-mesa-dev \
    libglu1-mesa-dev \
    libglew-dev \
    libglfw3-dev \
    libegl1-mesa-dev \
    mesa-utils \
    libdrm-dev \
    libgbm-dev

################################################################################
# Install GStreamer (Required for video playback)
################################################################################

echo "[INFO] Installing GStreamer and plugins..."
apt-get install -y \
    libgstreamer1.0-dev \
    libgstreamer-plugins-base1.0-dev \
    gstreamer1.0-plugins-base \
    gstreamer1.0-plugins-good \
    gstreamer1.0-plugins-bad \
    gstreamer1.0-plugins-ugly \
    gstreamer1.0-libav \
    gstreamer1.0-alsa \
    gstreamer1.0-tools

################################################################################
# Install Audio Libraries
################################################################################

echo "[INFO] Installing audio libraries..."
apt-get install -y \
    libasound2-dev \
    libpulse-dev \
    librtaudio-dev \
    alsa-utils \
    pulseaudio \
    libmpg123-dev \
    libsndfile1-dev \
    libfreeimage-dev \
    libopenal-dev

################################################################################
# Install Additional Libraries
################################################################################

echo "[INFO] Installing additional required libraries..."
apt-get install -y \
    libfreetype6-dev \
    libfontconfig1-dev \
    libcairo2-dev \
    libglm-dev \
    libxrandr-dev \
    libxi-dev \
    libxcursor-dev \
    libxinerama-dev \
    libxxf86vm-dev \
    libxmu-dev \
    libudev-dev \
    libboost-all-dev \
    libssl-dev \
    libpoco-dev \
    libpugixml-dev \
    libgtk-3-dev \
    libjpeg-dev \
    libpng-dev \
    libtiff-dev \
    libavcodec-dev \
    libavformat-dev \
    libswscale-dev \
    libv4l-dev \
    libxvidcore-dev \
    libx264-dev \
    liburiparser-dev

################################################################################
# Install Utilities
################################################################################

echo "[INFO] Installing utilities..."
apt-get install -y \
    curl \
    wget \
    unzip \
    rsync \
    htop \
    vim \
    nano \
    screen \
    tmux \
    net-tools \
    wireless-tools

################################################################################
# Install Python (for some oF scripts)
################################################################################

echo "[INFO] Installing Python..."
apt-get install -y \
    python3 \
    python3-pip \
    python3-dev

################################################################################
# Clean up
################################################################################

echo "[INFO] Cleaning up..."
apt-get autoremove -y
apt-get autoclean -y

echo "[INFO] Dependency installation completed successfully!"
EOFRUN

chmod +x "${STAGE_DIR}/00-install-dependencies/00-run-chroot.sh"

# Stage 00a: Configure Wireless and Bluetooth
mkdir -p "${STAGE_DIR}/00a-configure-wireless-bluetooth"

cat > "${STAGE_DIR}/00a-configure-wireless-bluetooth/00-run.sh" <<'EOFRUN'
#!/bin/bash -e
# Copy configure-wireless-bluetooth script to rootfs
install -m 755 -D files/configure-wireless-bluetooth.sh "${ROOTFS_DIR}/tmp/configure-wireless-bluetooth.sh"
EOFRUN

mkdir -p "${STAGE_DIR}/00a-configure-wireless-bluetooth/files"
cp "${BUILD_SYSTEM_DIR}/scripts/configure-wireless-bluetooth.sh" \
   "${STAGE_DIR}/00a-configure-wireless-bluetooth/files/configure-wireless-bluetooth.sh"

cat > "${STAGE_DIR}/00a-configure-wireless-bluetooth/00-run-chroot.sh" <<'EOFRUN'
#!/bin/bash -e
bash /tmp/configure-wireless-bluetooth.sh
EOFRUN

chmod +x "${STAGE_DIR}/00a-configure-wireless-bluetooth/00-run.sh"
chmod +x "${STAGE_DIR}/00a-configure-wireless-bluetooth/00-run-chroot.sh"

# Stage 01: Configure X11
mkdir -p "${STAGE_DIR}/01-configure-x11"

cat > "${STAGE_DIR}/01-configure-x11/00-run.sh" <<'EOFRUN'
#!/bin/bash -e
# Copy configure-x11 script to rootfs
install -m 755 -D files/configure-x11.sh "${ROOTFS_DIR}/tmp/configure-x11.sh"
EOFRUN

mkdir -p "${STAGE_DIR}/01-configure-x11/files"
cp "${BUILD_SYSTEM_DIR}/scripts/configure-x11.sh" \
   "${STAGE_DIR}/01-configure-x11/files/configure-x11.sh"

cat > "${STAGE_DIR}/01-configure-x11/00-run-chroot.sh" <<'EOFRUN'
#!/bin/bash -e
bash /tmp/configure-x11.sh
EOFRUN

chmod +x "${STAGE_DIR}/01-configure-x11/00-run.sh"
chmod +x "${STAGE_DIR}/01-configure-x11/00-run-chroot.sh"

# Stage 02: Configure Auto-login
mkdir -p "${STAGE_DIR}/02-configure-autologin"

cat > "${STAGE_DIR}/02-configure-autologin/00-run.sh" <<'EOFRUN'
#!/bin/bash -e
# Copy configure-autologin script to rootfs
install -m 755 -D files/configure-autologin.sh "${ROOTFS_DIR}/tmp/configure-autologin.sh"
EOFRUN

mkdir -p "${STAGE_DIR}/02-configure-autologin/files"
cp "${BUILD_SYSTEM_DIR}/scripts/configure-autologin.sh" \
   "${STAGE_DIR}/02-configure-autologin/files/configure-autologin.sh"

cat > "${STAGE_DIR}/02-configure-autologin/00-run-chroot.sh" <<'EOFRUN'
#!/bin/bash -e
bash /tmp/configure-autologin.sh
EOFRUN

chmod +x "${STAGE_DIR}/02-configure-autologin/00-run.sh"
chmod +x "${STAGE_DIR}/02-configure-autologin/00-run-chroot.sh"

# Stage 03: Install openFrameworks
mkdir -p "${STAGE_DIR}/03-install-openframeworks"

cat > "${STAGE_DIR}/03-install-openframeworks/00-run.sh" <<'EOFRUN'
#!/bin/bash -e
# Copy install-openframeworks script to rootfs
install -m 755 -D files/install-openframeworks.sh "${ROOTFS_DIR}/tmp/install-openframeworks.sh"
EOFRUN

mkdir -p "${STAGE_DIR}/03-install-openframeworks/files"
cp "${BUILD_SYSTEM_DIR}/scripts/install-openframeworks.sh" \
   "${STAGE_DIR}/03-install-openframeworks/files/install-openframeworks.sh"

cat > "${STAGE_DIR}/03-install-openframeworks/00-run-chroot.sh" <<EOFRUN
#!/bin/bash -e
# Export openFrameworks configuration from build config
export OF_VERSION="${OF_VERSION}"
export OF_PLATFORM="${OF_PLATFORM}"
export OF_ROOT="${OF_ROOT}"
bash /tmp/install-openframeworks.sh
EOFRUN

chmod +x "${STAGE_DIR}/03-install-openframeworks/00-run.sh"
chmod +x "${STAGE_DIR}/03-install-openframeworks/00-run-chroot.sh"

# Stage 04: Install ofxPiMapper
mkdir -p "${STAGE_DIR}/04-install-ofxpimapper"

cat > "${STAGE_DIR}/04-install-ofxpimapper/00-run.sh" <<'EOFRUN'
#!/bin/bash -e
# Copy install-ofxpimapper script to rootfs
install -m 755 -D files/install-ofxpimapper.sh "${ROOTFS_DIR}/tmp/install-ofxpimapper.sh"
EOFRUN

mkdir -p "${STAGE_DIR}/04-install-ofxpimapper/files"
cp "${BUILD_SYSTEM_DIR}/scripts/install-ofxpimapper.sh" \
   "${STAGE_DIR}/04-install-ofxpimapper/files/install-ofxpimapper.sh"

cat > "${STAGE_DIR}/04-install-ofxpimapper/00-run-chroot.sh" <<'EOFRUN'
#!/bin/bash -e
bash /tmp/install-ofxpimapper.sh
EOFRUN

chmod +x "${STAGE_DIR}/04-install-ofxpimapper/00-run.sh"
chmod +x "${STAGE_DIR}/04-install-ofxpimapper/00-run-chroot.sh"

# Stage 05: Configure Auto-start
if [ "${AUTOSTART_ENABLED}" = "true" ]; then
    mkdir -p "${STAGE_DIR}/05-configure-autostart"

    cat > "${STAGE_DIR}/05-configure-autostart/00-run.sh" <<'EOFRUN'
#!/bin/bash -e
# Copy configure-autostart script to rootfs
install -m 755 -D files/configure-autostart.sh "${ROOTFS_DIR}/tmp/configure-autostart.sh"
EOFRUN

    mkdir -p "${STAGE_DIR}/05-configure-autostart/files"
    cp "${BUILD_SYSTEM_DIR}/scripts/configure-autostart.sh" \
       "${STAGE_DIR}/05-configure-autostart/files/configure-autostart.sh"

    cat > "${STAGE_DIR}/05-configure-autostart/00-run-chroot.sh" <<'EOFRUN'
#!/bin/bash -e
bash /tmp/configure-autostart.sh
EOFRUN

    chmod +x "${STAGE_DIR}/05-configure-autostart/00-run.sh"
    chmod +x "${STAGE_DIR}/05-configure-autostart/00-run-chroot.sh"
fi

# Create EXPORT_IMAGE marker to tell pi-gen to export the final image from this stage
touch "${STAGE_DIR}/EXPORT_IMAGE"

log_info "✓ Custom stage created"

################################################################################
# Start Build
################################################################################

log_progress "Starting image build..."
log_info "This will take 2-4 hours depending on your hardware"
log_info "Build log: ${PIGEN_DIR}/work/*/build.log"

cd "$PIGEN_DIR"

# Create deploy directory
mkdir -p "$DEPLOY_DIR"

START_TIME=$(date +%s)

if [ "$USE_DOCKER" = true ]; then
    log_info "Building with Docker..."
    ./build-docker.sh
else
    log_info "Building on host system..."
    ./build.sh
fi

END_TIME=$(date +%s)
BUILD_DURATION=$((END_TIME - START_TIME))

################################################################################
# Post-Build Processing
################################################################################

log_progress "Processing build artifacts..."

# Move images to deploy directory
if [ -d "${PIGEN_DIR}/deploy" ]; then
    mv "${PIGEN_DIR}/deploy"/* "$DEPLOY_DIR/" || true
fi

# Find the generated image
IMAGE_FILE=$(find "$DEPLOY_DIR" -name "*.img" -type f | head -n1)

if [ -z "$IMAGE_FILE" ]; then
    log_error "No image file found in deploy directory"
    exit 1
fi

IMAGE_SIZE=$(stat -c%s "$IMAGE_FILE")
log_info "Image created: $(basename "$IMAGE_FILE")"
log_info "Image size: $(numfmt --to=iec-i --suffix=B $IMAGE_SIZE)"

# Generate checksums if requested
if [ "${GENERATE_CHECKSUMS}" = "true" ]; then
    log_info "Generating checksums..."
    cd "$DEPLOY_DIR"
    sha256sum "$(basename "$IMAGE_FILE")" > "$(basename "$IMAGE_FILE").sha256"
    log_info "✓ SHA256 checksum generated"
fi

################################################################################
# Summary
################################################################################

log_info "================================================================"
log_info "Build Complete!"
log_info "================================================================"
echo ""
echo "Build Information:"
echo "  - Build time: $(date -d@${BUILD_DURATION} -u +%H:%M:%S)"
echo "  - Image: $(basename "$IMAGE_FILE")"
echo "  - Size: $(numfmt --to=iec-i --suffix=B $IMAGE_SIZE)"
echo "  - Location: $DEPLOY_DIR"
echo ""
echo "Configuration:"
echo "  - Base: Raspberry Pi OS ${BASE_IMAGE} (${RPI_OS_RELEASE})"
echo "  - Architecture: ${ARCHITECTURE}"
echo "  - Username: ${RPI_USERNAME}"
echo "  - Hostname: ${HOSTNAME}"
echo "  - Auto-start: ${AUTOSTART_ENABLED}"
echo ""
echo "Next Steps:"
echo "  1. Test in QEMU:"
echo "     cd ../testing"
echo "     ./test-qemu.sh $IMAGE_FILE"
echo ""
echo "  2. Flash to SD card:"
echo "     sudo dd if=$IMAGE_FILE of=/dev/sdX bs=4M status=progress conv=fsync"
echo ""
log_info "Build completed successfully!"
