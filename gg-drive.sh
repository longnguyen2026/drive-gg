#!/usr/bin/env bash
#=========================================================
# Universal Google Drive Integrator (Mint & Kubuntu/Ubuntu)
# Author : Long Nguyen
# Script  : install-google-drive.sh
# Version : 2.0
#=========================================================

set -Eeuo pipefail

#=========================================================
# GLOBAL VARIABLES & COLORS
#=========================================================
SCRIPT_NAME="$(basename "$0")"
START_TIME=$(date +%s)

RED="\033[1;31m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
BLUE="\033[1;34m"
CYAN="\033[1;36m"
NC="\033[0m"

log()     { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; }
success() { echo -e "${CYAN}[ OK ]${NC} $1"; }
die()     { error "$1"; exit 1; }

trap 'error "Script failed at line $LINENO"; exit 1' ERR

clear
echo -e "${BLUE}====================================================="
echo "       Google Drive Integrator (Mint & Kubuntu)      "
echo -e "=====================================================${NC}"

#=========================================================
# SYSTEM CHECKS
#=========================================================
if [[ $EUID -eq 0 ]]; then
    die "Vui lòng KHÔNG chạy script này với quyền root trực tiếp.\nChạy với user thường: bash $SCRIPT_NAME"
fi

if [[ ! -f /etc/os-release ]]; then
    die "Không thể nhận diện hệ điều hành."
fi

source /etc/os-release
DESKTOP="${XDG_CURRENT_DESKTOP:-Unknown}"

log "Hệ điều hành : $NAME ${VERSION_ID:-}"
log "Desktop Env  : $DESKTOP"

# Xác thực distro
if [[ "$NAME" != *"Linux Mint"* ]] && [[ "$NAME" != *"Ubuntu"* ]] && [[ "$NAME" != *"Kubuntu"* ]]; then
    die "Hệ điều hành chưa được hỗ trợ: $NAME. Chỉ hỗ trợ Linux Mint và Ubuntu/Kubuntu."
fi

# Kiểm tra kết nối Internet
log "Kiểm tra kết nối mạng..."
if ping -c1 -W3 8.8.8.8 >/dev/null 2>&1; then
    success "Kết nối mạng: OK"
else
    die "Không có kết nối Internet."
fi

# Xác thực quyền sudo
sudo -v || die "Xác thực sudo thất bại."

#=========================================================
# PACKAGE INSTALLATION BASED ON DESKTOP
#=========================================================
log "======================================="
log "Cập nhật Package Index và Cài đặt..."
log "======================================="

sudo apt update

PACKAGES=()

if [[ "$DESKTOP" == *"KDE"* ]]; then
    log "Nhận diện môi trường KDE Plasma (Kubuntu). Cài đặt kio-gdrive..."
    PACKAGES=(
        kio-gdrive
        kaccounts-providers
        kaccounts-integration
    )
else
    log "Nhận diện môi trường Cinnamon/GNOME (Mint/Ubuntu). Cài đặt GVFS & GOA..."
    PACKAGES=(
        gnome-online-accounts
        gnome-control-center
        gvfs
        gvfs-backends
        gvfs-fuse
        seahorse
    )
fi

MISSING_PACKAGES=()
for pkg in "${PACKAGES[@]}"; do
    if dpkg -s "$pkg" >/dev/null 2>&1; then
        success "$pkg: Đã được cài đặt."
    else
        warn "$pkg: Còn thiếu."
        MISSING_PACKAGES+=("$pkg")
    fi
done

if [ ${#MISSING_PACKAGES[@]} -ne 0 ]; then
    log "Đang cài đặt các gói còn thiếu..."
    sudo apt install -y "${MISSING_PACKAGES[@]}"
    success "Cài đặt gói hoàn tất."
fi

#=========================================================
# POST-INSTALL CONFIGURATION & LAUNCH
#=========================================================
log "======================================="
log "Khởi chạy Cấu hình Tài khoản..."
log "======================================="

if [[ "$DESKTOP" == *"KDE"* ]]; then
    # Khởi chạy trên KDE
    (
        sleep 2
        kcmshell6 kcm_kaccounts >/dev/null 2>&1 || kcmshell5 kcm_kaccounts >/dev/null 2>&1 || systemsettings5 kcm_kaccounts >/dev/null 2>&1 &
    )
    
    cat <<EOF

Các bước tiếp theo trên Kubuntu (KDE Plasma):
--------------------------------------------
1. Cửa sổ "Online Accounts" (Tài khoản trực tuyến) sẽ mở ra.
2. Nhấp vào "Add New Account" -> Chọn "Google".
3. Tiến hành đăng nhập trên trình duyệt và cấp quyền.
4. Mở trình quản lý file Dolphin -> Chọn mục "Network" (hoặc Mạng) -> "Google Drive".

EOF
else
    # Khởi chạy trên Cinnamon / GNOME
    pkill gvfsd >/dev/null 2>&1 || true
    pkill goa-daemon >/dev/null 2>&1 || true
    sleep 1

    /usr/libexec/gvfsd >/dev/null 2>&1 &
    /usr/libexec/goa-daemon >/dev/null 2>&1 &

    (
        sleep 2
        gnome-control-center online-accounts >/dev/null 2>&1 &
    )

    cat <<EOF

Các bước tiếp theo trên Linux Mint:
--------------------------------------------
1. Cửa sổ Online Accounts sẽ mở ra.
2. Chọn "Google" và đăng nhập tài khoản.
3. Bật mục "Files" (Tệp tin).
4. Mở File Manager (Nemo), Google Drive sẽ xuất hiện ở thanh bên trái.

EOF
fi

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

echo "========================================="
echo "Đã thiết lập hoàn tất sau ${ELAPSED} giây."
echo "========================================="
exit 0
