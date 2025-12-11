#!/bin/bash
################################################################################
# Install ofxPiMapper and Required Addons
#
# This script clones ofxPiMapper and its dependencies, then compiles the
# specified example projects.
#
# Usage: ./install-ofxpimapper.sh [target_user]
################################################################################

set -e  # Exit on error
set -u  # Exit on undefined variable

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_progress() {
    echo -e "${BLUE}[PROGRESS]${NC} $1"
}

################################################################################
# Configuration
################################################################################

# Target user
TARGET_USER="${1:-${RPI_USERNAME:-$(whoami)}}"

# openFrameworks settings
OF_ROOT="${OF_ROOT:-/home/${TARGET_USER}/openFrameworks}"

# ofxPiMapper settings
OFXPIMAPPER_REPO="${OFXPIMAPPER_REPO:-https://github.com/b0rt/ofxPiMapper.git}"
OFXPIMAPPER_BRANCH="${OFXPIMAPPER_BRANCH:-master}"
COMPILE_EXAMPLE="${COMPILE_EXAMPLE:-example_simpler}"
ADDITIONAL_EXAMPLES="${ADDITIONAL_EXAMPLES:-example_basic}"

# Parallel jobs
PARALLEL_JOBS="${PARALLEL_JOBS:-$(nproc 2>/dev/null || echo 2)}"

log_info "Installing ofxPiMapper for ${TARGET_USER}"
log_info "openFrameworks: ${OF_ROOT}"
log_info "Repository: ${OFXPIMAPPER_REPO}"
log_info "Branch: ${OFXPIMAPPER_BRANCH}"

################################################################################
# Verify openFrameworks Installation
################################################################################

if [ ! -d "$OF_ROOT" ]; then
    log_error "openFrameworks not found at ${OF_ROOT}"
    log_error "Please install openFrameworks first"
    exit 1
fi

# Check if openFrameworks core library exists (handle glob pattern properly)
if ! ls "${OF_ROOT}/libs/openFrameworksCompiled/lib/"/*/libopenFrameworks.a >/dev/null 2>&1; then
    log_error "openFrameworks core library not compiled"
    log_error "Expected to find libopenFrameworks.a in ${OF_ROOT}/libs/openFrameworksCompiled/lib/"
    exit 1
fi

log_info "openFrameworks found at ${OF_ROOT}"

################################################################################
# Install Required Addons
################################################################################

ADDONS_DIR="${OF_ROOT}/addons"
mkdir -p "$ADDONS_DIR"

log_progress "Installing required addons..."

# Define required addons
# Format: "repo_url|branch|addon_name"
declare -a REQUIRED_ADDONS_LIST=(
    "https://github.com/pierrep/ofxOMXPlayer.git|SeekingFix|ofxOMXPlayer"
)

# Add optional addons if configured
if [ "${INSTALL_OPTIONAL_ADDONS:-true}" = "true" ]; then
    log_info "Installing optional addons..."
    REQUIRED_ADDONS_LIST+=(
        "https://github.com/pierrep/ofxVideoSync.git|master|ofxVideoSync"
    )
fi

# Install each addon
for addon_spec in "${REQUIRED_ADDONS_LIST[@]}"; do
    IFS='|' read -r repo branch name <<< "$addon_spec"

    log_info "Installing ${name}..."

    ADDON_PATH="${ADDONS_DIR}/${name}"

    if [ -d "$ADDON_PATH" ]; then
        log_warn "${name} already exists, updating..."
        cd "$ADDON_PATH"
        sudo -u "$TARGET_USER" git fetch origin
        sudo -u "$TARGET_USER" git checkout "$branch"
        sudo -u "$TARGET_USER" git pull origin "$branch"
    else
        log_info "Cloning ${name} from ${repo} (branch: ${branch})"
        sudo -u "$TARGET_USER" git clone -b "$branch" "$repo" "$ADDON_PATH"
    fi

    # Set ownership
    chown -R "${TARGET_USER}:${TARGET_USER}" "$ADDON_PATH"

    log_info "✓ ${name} installed"
done

################################################################################
# Install ofxPiMapper
################################################################################

log_progress "Installing ofxPiMapper..."

OFXPIMAPPER_PATH="${ADDONS_DIR}/ofxPiMapper"

if [ -d "$OFXPIMAPPER_PATH" ]; then
    log_warn "ofxPiMapper already exists, updating..."
    cd "$OFXPIMAPPER_PATH"
    sudo -u "$TARGET_USER" git fetch origin
    sudo -u "$TARGET_USER" git checkout "$OFXPIMAPPER_BRANCH"
    sudo -u "$TARGET_USER" git pull origin "$OFXPIMAPPER_BRANCH"
else
    log_info "Cloning ofxPiMapper from ${OFXPIMAPPER_REPO} (branch: ${OFXPIMAPPER_BRANCH})"
    sudo -u "$TARGET_USER" git clone -b "$OFXPIMAPPER_BRANCH" "$OFXPIMAPPER_REPO" "$OFXPIMAPPER_PATH"
fi

# Set ownership
chown -R "${TARGET_USER}:${TARGET_USER}" "$OFXPIMAPPER_PATH"

log_info "✓ ofxPiMapper installed"

################################################################################
# Fix addons.make Files for Raspberry Pi
################################################################################

log_info "Configuring addon dependencies..."

cd "$OFXPIMAPPER_PATH"

# Function to ensure addon is in addons.make
ensure_addon_in_make() {
    local example_dir="$1"
    local addon_name="$2"

    if [ -f "${example_dir}/addons.make" ]; then
        if ! grep -q "^${addon_name}$" "${example_dir}/addons.make"; then
            log_info "Adding ${addon_name} to ${example_dir}/addons.make"
            echo "$addon_name" >> "${example_dir}/addons.make"
        fi
    fi
}

# Add core dependencies to all examples
for example in example_* ; do
    if [ -d "$example" ]; then
        log_info "Configuring ${example}..."

        # Ensure ofxPiMapper is listed
        ensure_addon_in_make "$example" "ofxPiMapper"

        # Add platform-specific addons
        if [ -f /proc/device-tree/model ] && grep -q "Raspberry Pi" /proc/device-tree/model; then
            # Only add ofxOMXPlayer on Raspberry Pi
            if [ -d "${ADDONS_DIR}/ofxOMXPlayer" ]; then
                ensure_addon_in_make "$example" "ofxOMXPlayer"
            fi

            # Add camera support if present
            if [ -d "${ADDONS_DIR}/ofxRPiCameraVideoGrabber" ]; then
                ensure_addon_in_make "$example" "ofxRPiCameraVideoGrabber"
            fi
        fi

        # Add optional addons if present
        if [ -d "${ADDONS_DIR}/ofxVideoSync" ]; then
            ensure_addon_in_make "$example" "ofxVideoSync"
        fi

        # Set ownership
        chown -R "${TARGET_USER}:${TARGET_USER}" "$example"
    fi
done

################################################################################
# Create Sample Media Directory
################################################################################

log_info "Setting up sample media directories..."

setup_media_dir() {
    local example_dir="$1"
    local sources_dir="${example_dir}/bin/data/sources"

    mkdir -p "${sources_dir}/videos"
    mkdir -p "${sources_dir}/images"

    chown -R "${TARGET_USER}:${TARGET_USER}" "${example_dir}/bin/data"

    log_info "✓ Media directories created for ${example_dir##*/}"
}

# Setup media directories for main examples
for example in example_simpler example_basic example_fbo-sources; do
    if [ -d "$example" ]; then
        setup_media_dir "$example"
    fi
done

################################################################################
# Copy Sample Media (if available)
################################################################################

SAMPLE_MEDIA_DIR="${SAMPLE_MEDIA_DIR:-/tmp/sample-media}"

if [ "${INCLUDE_SAMPLE_MEDIA:-true}" = "true" ] && [ -d "$SAMPLE_MEDIA_DIR" ]; then
    log_info "Copying sample media files..."

    for example in example_simpler example_basic; do
        if [ -d "$example" ]; then
            DEST_DIR="${example}/bin/data/sources"

            # Copy sample videos
            if [ -d "${SAMPLE_MEDIA_DIR}/videos" ]; then
                cp -r "${SAMPLE_MEDIA_DIR}/videos"/* "${DEST_DIR}/videos/" 2>/dev/null || true
            fi

            # Copy sample images
            if [ -d "${SAMPLE_MEDIA_DIR}/images" ]; then
                cp -r "${SAMPLE_MEDIA_DIR}/images"/* "${DEST_DIR}/images/" 2>/dev/null || true
            fi

            chown -R "${TARGET_USER}:${TARGET_USER}" "$DEST_DIR"
        fi
    done
fi

################################################################################
# Compile Examples
################################################################################

log_progress "Compiling ofxPiMapper examples..."
log_info "This may take 20-40 minutes..."

COMPILE_FAILED=0

# Function to compile an example
compile_example() {
    local example_name="$1"
    local example_dir="${OFXPIMAPPER_PATH}/${example_name}"

    if [ ! -d "$example_dir" ]; then
        log_warn "Example not found: ${example_name}"
        return 1
    fi

    log_info "Compiling ${example_name}..."
    cd "$example_dir"

    # Clean previous builds
    sudo -u "$TARGET_USER" make clean || true

    # Compile
    if sudo -u "$TARGET_USER" make -j${PARALLEL_JOBS} 2>&1 | tee "/tmp/compile_${example_name}.log"; then
        log_info "✓ ${example_name} compiled successfully"

        # Verify binary
        local binary_path="bin/${example_name}"
        if [ -f "$binary_path" ]; then
            chmod +x "$binary_path"
            chown "${TARGET_USER}:${TARGET_USER}" "$binary_path"
            log_info "  Binary: ${binary_path} ($(stat -c%s "$binary_path" | numfmt --to=iec-i --suffix=B))"
            return 0
        else
            log_error "Binary not found: ${binary_path}"
            return 1
        fi
    else
        log_error "✗ ${example_name} compilation failed"
        log_info "  Check log: /tmp/compile_${example_name}.log"
        tail -n 30 "/tmp/compile_${example_name}.log"
        return 1
    fi
}

# Compile main example
if ! compile_example "$COMPILE_EXAMPLE"; then
    COMPILE_FAILED=1
fi

# Compile additional examples
if [ -n "$ADDITIONAL_EXAMPLES" ]; then
    for example in $ADDITIONAL_EXAMPLES; do
        compile_example "$example" || COMPILE_FAILED=1
    done
fi

################################################################################
# Create Launch Scripts
################################################################################

log_info "Creating launch scripts..."

create_launch_script() {
    local example_name="$1"
    local example_dir="${OFXPIMAPPER_PATH}/${example_name}"

    if [ ! -d "$example_dir" ]; then
        return
    fi

    local script_path="${example_dir}/launch.sh"

    cat > "$script_path" <<EOFSCRIPT
#!/bin/bash
# Launch script for ${example_name}

SCRIPT_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
cd "\$SCRIPT_DIR"

# Export openFrameworks environment
export OF_ROOT="${OF_ROOT}"

# Launch the application
# Use -f flag for fullscreen
./bin/${example_name} "\$@"
EOFSCRIPT

    chmod +x "$script_path"
    chown "${TARGET_USER}:${TARGET_USER}" "$script_path"

    log_info "✓ Created launch script: ${script_path}"
}

create_launch_script "$COMPILE_EXAMPLE"
for example in $ADDITIONAL_EXAMPLES; do
    create_launch_script "$example"
done

################################################################################
# Summary
################################################################################

log_info "================================================================"
log_info "ofxPiMapper Installation Complete!"
log_info "================================================================"
echo ""
echo "Installation Details:"
echo "  - Location: ${OFXPIMAPPER_PATH}"
echo "  - Branch: ${OFXPIMAPPER_BRANCH}"
echo "  - User: ${TARGET_USER}"
echo ""
echo "Compiled Examples:"

for example in $COMPILE_EXAMPLE $ADDITIONAL_EXAMPLES; do
    if [ -f "${OFXPIMAPPER_PATH}/${example}/bin/${example}" ]; then
        echo "  ✓ ${example}"
    else
        echo "  ✗ ${example} (failed to compile)"
    fi
done

echo ""
echo "To run ofxPiMapper:"
echo "  cd ${OFXPIMAPPER_PATH}/${COMPILE_EXAMPLE}"
echo "  ./launch.sh"
echo ""
echo "Or in fullscreen:"
echo "  ./launch.sh -f"
echo ""

if [ $COMPILE_FAILED -ne 0 ]; then
    log_warn "Some examples failed to compile. Check the logs in /tmp/compile_*.log"
    exit 1
fi

log_info "Installation successful!"
