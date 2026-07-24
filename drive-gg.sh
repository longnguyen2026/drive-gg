#=========================================================
# PART 1/8
# Initialize Script
#=========================================================

#!/usr/bin/env bash
#
#=========================================================
# Google Drive Installer for Linux Mint
# Author : Long Nguyen
# Script  : install-google-drive.sh
# Version : 1.0
#=========================================================

set -Eeuo pipefail

#=========================================================
# GLOBAL VARIABLES
#=========================================================

SCRIPT_NAME="$(basename "$0")"
START_TIME=$(date +%s)

DISTRO="Linux Mint"
SUPPORTED_VERSION="22.3"
SUPPORTED_DESKTOP="Cinnamon"

#=========================================================
# COLORS
#=========================================================

RED="\033[1;31m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
BLUE="\033[1;34m"
CYAN="\033[1;36m"
WHITE="\033[1;37m"
NC="\033[0m"

#=========================================================
# LOG FUNCTIONS
#=========================================================

log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

success() {
    echo -e "${CYAN}[ OK ]${NC} $1"
}

die() {
    error "$1"
    exit 1
}

#=========================================================
# ERROR HANDLER
#=========================================================

trap 'error "Script failed at line $LINENO"; exit 1' ERR

#=========================================================
# HEADER
#=========================================================

clear

echo -e "${BLUE}"
echo "====================================================="
echo "        Google Drive Installer for Linux Mint"
echo "====================================================="
echo -e "${NC}"

log "Starting installation..."
log "Script : $SCRIPT_NAME"
log "Date   : $(date)"
echo

#=========================================================
# PART 2/8
# System Checks
#=========================================================

log "======================================="
log "Checking System Requirements..."
log "======================================="

#---------------------------------------------------------
# Check Root
#---------------------------------------------------------
if [[ $EUID -eq 0 ]]; then
    die "Please DO NOT run this script as root.
Run it as a normal user:
bash install-google-drive.sh"
fi

#---------------------------------------------------------
# Check Linux Mint
#---------------------------------------------------------
if [[ ! -f /etc/os-release ]]; then
    die "Cannot detect operating system."
fi

source /etc/os-release

if [[ "$NAME" != "Linux Mint" ]]; then
    die "Unsupported operating system.

Detected : $NAME
Required : Linux Mint"
fi

success "Operating System : $NAME $VERSION_ID"

#---------------------------------------------------------
# Check Cinnamon Desktop
#---------------------------------------------------------
DESKTOP="${XDG_CURRENT_DESKTOP:-Unknown}"

if [[ "$DESKTOP" != *"Cinnamon"* ]]; then
    warn "Current desktop : $DESKTOP"
    warn "This installer is optimized for Cinnamon."
else
    success "Desktop : $DESKTOP"
fi

#---------------------------------------------------------
# Check Architecture
#---------------------------------------------------------
ARCH=$(dpkg --print-architecture)

if [[ "$ARCH" != "amd64" ]]; then
    warn "Architecture : $ARCH"
else
    success "Architecture : $ARCH"
fi

#---------------------------------------------------------
# Check Internet Connection
#---------------------------------------------------------
log "Checking Internet connection..."

if ping -c1 -W3 8.8.8.8 >/dev/null 2>&1; then
    success "Internet connection OK."
else
    die "No Internet connection detected."
fi

#---------------------------------------------------------
# Check sudo Permission
#---------------------------------------------------------
if sudo -n true 2>/dev/null; then
    success "sudo permission OK."
else
    log "Requesting administrator password..."
    sudo -v || die "Administrator authentication failed."
fi

#---------------------------------------------------------
# Check Available Disk Space
#---------------------------------------------------------
FREE_SPACE=$(df --output=avail -BG "$HOME" | tail -1 | tr -dc '0-9')

if (( FREE_SPACE < 2 )); then
    die "Not enough free disk space.
Required : 2 GB
Available: ${FREE_SPACE} GB"
fi

success "Available Disk Space : ${FREE_SPACE} GB"

echo
success "System requirements passed."
echo

#=========================================================
# PART 3/8
# Update System & Install Required Packages
#=========================================================

log "======================================="
log "Updating Package Index..."
log "======================================="

sudo apt update

success "Package index updated."

echo

log "======================================="
log "Checking Required Packages..."
log "======================================="

PACKAGES=(
    gnome-online-accounts
    gnome-control-center
    gvfs
    gvfs-backends
    gvfs-fuse
    libnss3-tools
    seahorse
)

MISSING_PACKAGES=()

for pkg in "${PACKAGES[@]}"; do
    if dpkg -s "$pkg" >/dev/null 2>&1; then
        success "$pkg is already installed."
    else
        warn "$pkg is missing."
        MISSING_PACKAGES+=("$pkg")
    fi
done

echo

if [ ${#MISSING_PACKAGES[@]} -eq 0 ]; then
    success "All required packages are already installed."
else
    log "Installing required packages..."

    sudo apt install -y "${MISSING_PACKAGES[@]}"

    success "Package installation completed."
fi

echo

log "Cleaning package cache..."

sudo apt autoremove -y
sudo apt autoclean -y

success "Package cleanup completed."

echo

#=========================================================
# PART 4/8
# Configure Google Drive
#=========================================================

log "======================================="
log "Configuring Google Drive Components..."
log "======================================="

#---------------------------------------------------------
# Check GVFS Backend
#---------------------------------------------------------
if command -v gio >/dev/null 2>&1; then
    success "gio detected."
else
    die "gio is not installed."
fi

#---------------------------------------------------------
# Check gnome-online-accounts
#---------------------------------------------------------
if command -v gnome-control-center >/dev/null 2>&1; then
    success "GNOME Control Center detected."
else
    die "gnome-control-center not found."
fi

#---------------------------------------------------------
# Restart GVFS Services
#---------------------------------------------------------
log "Restarting GVFS services..."

pkill gvfsd >/dev/null 2>&1 || true
pkill gvfs-goa-volume-monitor >/dev/null 2>&1 || true
pkill goa-daemon >/dev/null 2>&1 || true

sleep 2

/usr/libexec/gvfsd >/dev/null 2>&1 &
/usr/libexec/gvfs-goa-volume-monitor >/dev/null 2>&1 &
/usr/libexec/goa-daemon >/dev/null 2>&1 &

sleep 2

success "GVFS services restarted."

#---------------------------------------------------------
# Verify GOA Service
#---------------------------------------------------------
if pgrep -f goa-daemon >/dev/null 2>&1; then
    success "Google Online Accounts service is running."
else
    warn "Google Online Accounts service is not running."
fi

echo
success "Google Drive components configured."
echo

#=========================================================
# PART 5/8
# Verify Installation
#=========================================================

log "======================================="
log "Verifying Installation..."
log "======================================="

CHECK_PACKAGES=(
    gnome-online-accounts
    gnome-control-center
    gvfs
    gvfs-backends
    gvfs-fuse
    seahorse
)

FAILED=0

for pkg in "${CHECK_PACKAGES[@]}"; do
    if dpkg -s "$pkg" >/dev/null 2>&1; then
        success "$pkg ........ OK"
    else
        error "$pkg ........ NOT INSTALLED"
        FAILED=1
    fi
done

echo

log "Checking gio..."

if command -v gio >/dev/null 2>&1; then
    success "gio command detected."
else
    error "gio command not found."
    FAILED=1
fi

echo

log "Checking GVFS..."

if pgrep -x gvfsd >/dev/null 2>&1; then
    success "GVFS daemon is running."
else
    warn "GVFS daemon is not running."
fi

echo

log "Checking Google Online Accounts..."

if pgrep -f goa-daemon >/dev/null 2>&1; then
    success "Google Online Accounts daemon is running."
else
    warn "Google Online Accounts daemon is not running."
fi

echo

if [[ $FAILED -eq 0 ]]; then
    success "Verification completed successfully."
else
    die "Verification failed. Please review the errors above."
fi

echo

#=========================================================
# PART 6/8
# Launch Google Online Accounts
#=========================================================

log "======================================="
log "Launching Google Online Accounts..."
log "======================================="

if command -v gnome-control-center >/dev/null 2>&1; then

    log "Opening Online Accounts..."

    (
        sleep 2
        gnome-control-center online-accounts >/dev/null 2>&1 &
    )

    success "Google Online Accounts opened."

else
    warn "GNOME Control Center not found."
    warn "Please open it manually:"
    echo
    echo "Menu -> Settings -> Online Accounts"
    echo
fi

echo

log "======================================="
log "Next Step"
log "======================================="

cat <<EOF

1. Click "Google"

2. Sign in to your Google Account

3. Allow requested permissions

4. Make sure "Files" (Google Drive) is enabled

5. Close the window

6. Open File Manager (Nemo)

7. Your Google Drive will appear in the left sidebar.

EOF

echo

success "Waiting for user to complete Google sign-in..."


#=========================================================
# PART 7/8
# Sign-in google-drive
#=========================================================

#=========================================================
# PART 8/8
# Finish Installation
#=========================================================

log "======================================="
log "Google Drive Installation Completed"
log "======================================="

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

echo

success "Google Drive components have been installed."

echo
echo "========================================="
echo "Installation Summary"
echo "========================================="
echo "Operating System : $NAME $VERSION_ID"
echo "Desktop          : ${DESKTOP:-Unknown}"
echo "Architecture     : $ARCH"
echo "Script           : $SCRIPT_NAME"
echo "Elapsed Time     : ${ELAPSED} seconds"
echo

cat <<EOF

Next Steps
----------

1. Open:
   Menu → Settings → Online Accounts

2. Click:
   Google

3. Sign in with your Google account.

4. Enable:
   ✓ Files (Google Drive)

5. Open File Manager (Nemo).

Your Google Drive should appear in the left sidebar.

EOF

echo

warn "If Google Drive does not appear:"
echo "  • Log out and log back in."
echo "  • Or restart the computer."

echo
success "Installation completed successfully."
echo
exit 0
