#!/usr/bin/env bash
#=========================================================
# Universal Google Drive Integrator
# Linux Mint 22.x / Kubuntu 24.04+ / Ubuntu KDE
# Author  : Long Nguyen
# Script  : install-google-drive.sh
# Version : 2.1 ngày 09.11.2026
#=========================================================

set -Eeuo pipefail

SCRIPT_NAME="$(basename "$0")"
START_TIME=$(date +%s)

RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
NC='\033[0m'

log()     { printf "${GREEN}[INFO]${NC} %s\n" "$1"; }
warn()    { printf "${YELLOW}[WARN]${NC} %s\n" "$1"; }
error()   { printf "${RED}[ERROR]${NC} %s\n" "$1"; }
success() { printf "${CYAN}[ OK ]${NC} %s\n" "$1"; }
die()     { error "$1"; exit 1; }

trap 'error "Lỗi tại dòng $LINENO"; exit 1' ERR

clear 2>/dev/null || true

echo -e "${BLUE}"
echo "====================================================="
echo "          GOOGLE DRIVE INTEGRATOR 2.1"
echo "          Linux Mint / Kubuntu / Ubuntu KDE"
echo "          Author: Long Nguyen"
echo "====================================================="
echo -e "${NC}"

#=========================================================
# 1. SYSTEM CHECK
#=========================================================

[[ $EUID -ne 0 ]] || die \
"Không chạy script bằng root trực tiếp.
Hãy chạy: bash $SCRIPT_NAME"

[[ -f /etc/os-release ]] || die "Không nhận diện được hệ điều hành."

source /etc/os-release

OS_ID="${ID:-unknown}"
OS_NAME="${NAME:-Unknown}"
OS_VERSION="${VERSION_ID:-Unknown}"

DESKTOP_INFO="${XDG_CURRENT_DESKTOP:-} ${XDG_SESSION_DESKTOP:-} ${DESKTOP_SESSION:-}"
DESKTOP_INFO="${DESKTOP_INFO,,}"

IS_MINT=false
IS_KDE=false

[[ "$OS_ID" == "linuxmint" ]] && IS_MINT=true

if [[ "$DESKTOP_INFO" == *"kde"* ]] ||
   [[ "$DESKTOP_INFO" == *"plasma"* ]]; then
    IS_KDE=true
fi

log "Hệ điều hành: $OS_NAME $OS_VERSION"
log "Desktop: ${DESKTOP_INFO:-Unknown}"

#=========================================================
# 2. VALIDATE SUPPORTED SYSTEM
#=========================================================

if [[ "$IS_MINT" == true ]]; then

    log "Đã nhận diện Linux Mint."

elif [[ "$OS_ID" == "ubuntu" && "$IS_KDE" == true ]]; then

    log "Đã nhận diện Ubuntu/Kubuntu KDE Plasma."

else

    die "Hệ điều hành hoặc Desktop chưa được hỗ trợ.
Hỗ trợ:
- Linux Mint
- Kubuntu / Ubuntu KDE Plasma"

fi

#=========================================================
# 3. GRAPHICAL SESSION CHECK
#=========================================================

HAS_GUI=false

if [[ -n "${DISPLAY:-}" || -n "${WAYLAND_DISPLAY:-}" ]]; then
    HAS_GUI=true
fi

#=========================================================
# 4. SUDO CHECK
#=========================================================

log "Xác thực quyền quản trị..."

sudo -v || die "Không xác thực được sudo."

#=========================================================
# 5. UPDATE PACKAGE INDEX
#=========================================================

log "Cập nhật danh sách gói..."

sudo apt-get update

success "Cập nhật Package Index thành công."

#=========================================================
# 6. SELECT INSTALLATION METHOD
#=========================================================

PACKAGES=()
INSTALL_MODE=""

if [[ "$IS_MINT" == true ]]; then

    INSTALL_MODE="GVFS + GNOME Online Accounts GTK"

    log "Phương thức: Google Drive qua GVFS."

    PACKAGES=(
        gnome-online-accounts-gtk
        gvfs
        gvfs-backends
        gvfs-fuse
    )

elif [[ "$IS_KDE" == true ]]; then

    INSTALL_MODE="KIO GDrive"

    log "Phương thức: Google Drive qua KDE KIO."

    PACKAGES=(
        kio-gdrive
    )

fi

#=========================================================
# 7. CHECK PACKAGE AVAILABILITY
#=========================================================

log "Kiểm tra các gói cần thiết..."

MISSING_PACKAGES=()

for pkg in "${PACKAGES[@]}"; do

    if ! apt-cache show "$pkg" >/dev/null 2>&1; then
        die "Không tìm thấy gói $pkg trong kho APT.
Hãy kiểm tra nguồn phần mềm của hệ thống."
    fi

    if dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null |
       grep -q "install ok installed"; then

        success "$pkg: Đã cài đặt."

    else

        warn "$pkg: Chưa cài đặt."
        MISSING_PACKAGES+=("$pkg")

    fi

done

#=========================================================
# 8. INSTALL PACKAGES
#=========================================================

if (( ${#MISSING_PACKAGES[@]} > 0 )); then

    log "Đang cài đặt các gói còn thiếu..."

    sudo apt-get install -y "${MISSING_PACKAGES[@]}"

    success "Cài đặt hoàn tất."

else

    success "Tất cả gói cần thiết đã có."

fi

#=========================================================
# 9. VERIFY INSTALLATION
#=========================================================

log "Kiểm tra sau cài đặt..."

for pkg in "${PACKAGES[@]}"; do

    if dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null |
       grep -q "install ok installed"; then

        success "$pkg: OK"

    else

        die "Kiểm tra thất bại: $pkg"

    fi

done

#=========================================================
# 10. LAUNCH CONFIGURATION
#=========================================================

echo
log "Phương thức cài đặt: $INSTALL_MODE"

if [[ "$HAS_GUI" == true ]]; then

    if [[ "$IS_MINT" == true ]]; then

        if command -v gnome-online-accounts-gtk >/dev/null 2>&1; then

            log "Mở Google Online Accounts..."

            gnome-online-accounts-gtk >/dev/null 2>&1 &

        else

            warn "Không tìm thấy giao diện Online Accounts GTK."

        fi

        cat <<'EOF'

=====================================================
HƯỚNG DẪN SỬ DỤNG GOOGLE DRIVE - LINUX MINT
=====================================================

1. Chọn Add Account -> Google.
2. Đăng nhập tài khoản Google.
3. Cấp quyền truy cập.
4. Bật Files nếu tùy chọn này xuất hiện.
5. Mở Nemo -> Network.
6. Chọn Google Drive của tài khoản.

Lưu ý:
Tính năng này truy cập dữ liệu trực tuyến,
không tự động đồng bộ toàn bộ dữ liệu về máy.

=====================================================

EOF

    elif [[ "$IS_KDE" == true ]]; then

        if command -v systemsettings >/dev/null 2>&1; then

            log "Mở KDE System Settings..."

            systemsettings >/dev/null 2>&1 &

        else

            warn "Không tìm thấy KDE System Settings."

        fi

        cat <<'EOF'

=====================================================
HƯỚNG DẪN SỬ DỤNG GOOGLE DRIVE - KUBUNTU
=====================================================

1. Mở System Settings.
2. Tìm mục Online Accounts.
3. Chọn Add New Account -> Google.
4. Đăng nhập và cấp quyền.
5. Mở Dolphin.
6. Truy cập Google Drive trong Network.

Lưu ý:
KIO GDrive là trình truy cập dữ liệu trực tuyến
qua KDE, không phải công cụ đồng bộ offline.

=====================================================

EOF

    fi

else

    warn "Không phát hiện phiên đồ họa."
    warn "Các gói đã được cài đặt."
    warn "Hãy đăng nhập Desktop và mở Online Accounts để cấu hình."

fi

#=========================================================
# 11. SUMMARY
#=========================================================

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

echo
echo -e "${GREEN}====================================================="
echo "         GOOGLE DRIVE SETUP COMPLETED"
echo "====================================================="
echo -e "${NC}"

echo "Hệ điều hành : $OS_NAME $OS_VERSION"
echo "Phương thức  : $INSTALL_MODE"
echo "Thời gian    : ${ELAPSED} giây"

echo
success "Hoàn tất cài đặt Google Drive Integrator 2.1."

echo
echo "Lưu ý: Người dùng cần đăng nhập Google và cấp quyền."
echo "Script không xóa tài khoản hoặc dữ liệu hiện có."

exit 0
