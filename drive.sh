#!/usr/bin/env bash
#=========================================================
# Universal Google Drive Integrator
# Linux Mint 22.x / Kubuntu 24.04+ / Ubuntu KDE
# Author  : Long Nguyen
# Script  : install-google-drive.sh
# Version : 3.5 ngày 09.11.2026
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
echo "          GOOGLE DRIVE INTEGRATOR 3.5"
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

if [[ "$DESKTOP_INFO" == *"kde"* ]] || [[ "$DESKTOP_INFO" == *"plasma"* ]]; then
    IS_KDE=true
elif dpkg -l kubuntu-desktop >/dev/null 2>&1 || dpkg -l plasma-desktop >/dev/null 2>&1; then
    IS_KDE=true
fi

log "Hệ điều hành: $OS_NAME $OS_VERSION"
log "Desktop: ${DESKTOP_INFO:-Detected via installed packages}"

#=========================================================
# 2. VALIDATE SUPPORTED SYSTEM
#=========================================================

if [[ "$IS_MINT" == true ]]; then
    log "Đã nhận diện Linux Mint."
elif [[ "$OS_ID" == "ubuntu" && "$IS_KDE" == true ]]; then
    log "Đã nhận diện Ubuntu/Kubuntu KDE Plasma."
else
    die "Hệ điều hành hoặc Desktop chưa được hỗ trợ."
fi

#=========================================================
# 3. GRAPHICAL SESSION CHECK
#=========================================================

HAS_GUI=false
if [[ -n "${DISPLAY:-}" || -n "${WAYLAND_DISPLAY:-}" ]]; then
    HAS_GUI=true
fi

#=========================================================
# 4. SUDO CHECK & KEEPALIVE
#=========================================================

log "Xác thực quyền quản trị..."
sudo -v || die "Không xác thực được sudo."

while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
SUDO_PID=$!
trap 'kill "$SUDO_PID" 2>/dev/null || true; error "Lỗi tại dòng $LINENO"; exit 1' ERR

#=========================================================
# 5. UPDATE PACKAGE INDEX
#=========================================================

log "Cập nhật danh sách gói..."
sudo apt-get update
success "Cập nhật Package Index thành công."

#=========================================================
# 6. SELECT INSTALLATION METHOD & INSTALL
#=========================================================

TARGET_DIR="$HOME/GoogleDrive"
mkdir -p "$TARGET_DIR"

if [[ "$IS_MINT" == true ]]; then

    INSTALL_MODE="GVFS + GNOME Online Accounts GTK"
    log "Phương thức: Google Drive qua GVFS."

    PACKAGES=(
        gnome-online-accounts-gtk
        gvfs
        gvfs-backends
        gvfs-fuse
    )

    MISSING_PACKAGES=()
    for pkg in "${PACKAGES[@]}"; do
        if dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"; then
            success "$pkg: Đã cài đặt."
        else
            warn "$pkg: Chưa cài đặt."
            MISSING_PACKAGES+=("$pkg")
        fi
    done

    if (( ${#MISSING_PACKAGES[@]} > 0 )); then
        log "Đang cài đặt các gói còn thiếu..."
        sudo apt-get install -y "${MISSING_PACKAGES[@]}"
        success "Cài đặt hoàn tất."
    fi

elif [[ "$IS_KDE" == true ]]; then

    INSTALL_MODE="Rclone Native FUSE Mount"
    log "Phương thức: Google Drive qua Rclone FUSE (Dolphin Places)."

    PACKAGES=(
        rclone
        fuse3
    )

    MISSING_PACKAGES=()
    for pkg in "${PACKAGES[@]}"; do
        if dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"; then
            success "$pkg: Đã cài đặt."
        else
            warn "$pkg: Chưa cài đặt."
            MISSING_PACKAGES+=("$pkg")
        fi
    done

    if (( ${#MISSING_PACKAGES[@]} > 0 )); then
        log "Đang cài đặt các gói còn thiếu..."
        sudo apt-get install -y "${MISSING_PACKAGES[@]}"
        success "Cài đặt hoàn tất."
    fi

    # Cấu hình systemd user service chuẩn notify
    SERVICE_DIR="$HOME/.config/systemd/user"
    SERVICE_FILE="$SERVICE_DIR/rclone-gdrive.service"
    mkdir -p "$SERVICE_DIR"

    cat <<'EOF' > "$SERVICE_FILE"
[Unit]
Description=Mount Google Drive via Rclone
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
ExecStartPre=/bin/sh -c 'fusermount -uz %h/GoogleDrive 2>/dev/null || true'
ExecStart=/usr/bin/rclone mount drive: %h/GoogleDrive \
  --vfs-cache-mode full \
  --vfs-cache-max-age 24h \
  --vfs-read-chunk-size 32M \
  --buffer-size 32M \
  --dir-cache-time 72h
ExecStop=/bin/fusermount -uz %h/GoogleDrive
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF

    systemctl --user daemon-reload

fi

kill "$SUDO_PID" 2>/dev/null || true

#=========================================================
# 7. LAUNCH CONFIGURATION & FINISH
#=========================================================

echo
log "Phương thức cài đặt: $INSTALL_MODE"

if [[ "$IS_MINT" == true ]]; then

    if [[ "$HAS_GUI" == true ]] && command -v gnome-online-accounts-gtk >/dev/null 2>&1; then
        log "Mở Google Online Accounts..."
        gnome-online-accounts-gtk >/dev/null 2>&1 &
    fi

    cat <<'EOF'

=====================================================
HƯỚNG DẪN SỬ DỤNG GOOGLE DRIVE - LINUX MINT
=====================================================

1. Cửa sổ Online Accounts sẽ hiển thị -> Chọn Google.
2. Đăng nhập và cho phép cấp quyền.
3. Mở Nemo -> Chọn mục Network -> Chọn Google Drive.

=====================================================

EOF

elif [[ "$IS_KDE" == true ]]; then

    # Kiểm tra xem remote 'drive' đã có cấu hình và token hợp lệ chưa
    TOKEN_VALID=false
    if [[ -f "$HOME/.config/rclone/rclone.conf" ]]; then
        if grep -q "token =" "$HOME/.config/rclone/rclone.conf" 2>/dev/null; then
            TOKEN_VALID=true
        fi
    fi

    if [[ "$TOKEN_VALID" == false ]]; then
        echo
        echo -e "${YELLOW}=====================================================${NC}"
        echo -e "${YELLOW}       ĐANG KẾT NỐI TÀI KHOẢN GOOGLE DRIVE           ${NC}"
        echo -e "${YELLOW}=====================================================${NC}"
        echo "Script đang tự động nạp cấu hình (n -> drive -> drive -> 1 -> y -> n -> y -> q)."
        echo -e "${GREEN}>> TRÌNH DUYỆT SẼ TỰ ĐỘNG BẬT LÊN ĐỂ ĐĂNG NHẬP GMAIL.${NC}"
        echo -e "${GREEN}>> ANH CHỈ CẦN BẤM 'CHO PHÉP' (ALLOW) TRÊN WEB LÀ XONG!${NC}"
        echo "-----------------------------------------------------"

        # Tự động nạp sẵn chuỗi tương tác vào rclone config
        printf "n\ndrive\ndrive\n\n\n1\n\nn\ny\nn\ny\nq\n" | rclone config
    fi

    # Giải phóng thư mục nếu còn kẹt mount cũ
    fusermount -uz "$TARGET_DIR" 2>/dev/null || true

    log "Kích hoạt và nạp chạy Systemd Mount Service..."
    systemctl --user enable --now rclone-gdrive.service 2>/dev/null || true
    sleep 3

    # Ghim thư mục vào Dolphin Places (Xóa liên kết KIO cũ nếu có)
    USER_PLACES="$HOME/.local/share/user-places.xbel"
    if [[ -f "$USER_PLACES" ]]; then
        sed -i '/<bookmark href="gdrive:\/">/,/<\/bookmark>/d' "$USER_PLACES" 2>/dev/null || true
        sed -i '/<bookmark href="file:\/\/.*GoogleDrive">/,/<\/bookmark>/d' "$USER_PLACES" 2>/dev/null || true
        
        log "Ghim lối tắt Google Drive vào thanh điều hướng Dolphin..."
        sed -i 's|</xbel>||' "$USER_PLACES"
        cat <<EOF >> "$USER_PLACES"
 <bookmark href="file://$TARGET_DIR">
  <title>Google Drive</title>
  <info>
   <metadata owner="http://freedesktop.org">
    <bookmark:icon name="folder-cloud"/>
   </metadata>
   <metadata owner="http://www.kde.org">
    <ID>$(date +%s%N)</ID>
    <IsHidden>false</IsHidden>
   </metadata>
  </info>
 </bookmark>
</xbel>
EOF
    fi

    cat <<EOF

=====================================================
HƯỚNG DẪN SỬ DỤNG GOOGLE DRIVE - KUBUNTU / KDE
=====================================================

1. Thư mục gắn tại máy : $TARGET_DIR
2. Trạng thái kết nối   :
EOF

    if systemctl --user is-active --quiet rclone-gdrive.service; then
        cat <<'EOF'
   -> KẾT NỐI THÀNH CÔNG (Active Running).
   -> File đã sẵn sàng trong Dolphin -> Cột Places bên trái!
EOF
    else
        cat <<'EOF'
   -> CHƯA KÍCH HOẠT: Hãy đảm bảo đã hoàn tất xác thực trên trình duyệt.
   -> Chạy lại script để kích hoạt service.
EOF
    fi

    cat <<'EOF'
=====================================================

EOF

fi

#=========================================================
# 8. SUMMARY
#=========================================================

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

echo -e "${GREEN}====================================================="
echo "         GOOGLE DRIVE SETUP COMPLETED"
echo "====================================================="
echo -e "${NC}"

echo "Hệ điều hành : $OS_NAME $OS_VERSION"
echo "Phương thức  : $INSTALL_MODE"
echo "Thời gian    : ${ELAPSED} giây"

echo
success "Hoàn tất cài đặt Google Drive Integrator 3.5."

exit 0
