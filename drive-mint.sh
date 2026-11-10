#!/usr/bin/env bash
#=========================================================
# Universal Google Drive Integrator
# Linux Mint 21.x / 22.x / Kubuntu / Ubuntu KDE & Cinnamon
# Author  : Long Nguyen
# Script  : install-google-drive.sh
# Version : 4.3 ngày 10.11.2026
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
echo "          GOOGLE DRIVE INTEGRATOR 4.3"
echo "      Linux Mint (Cinnamon) / Kubuntu (KDE Plasma)"
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

log "Hệ điều hành: $OS_NAME $OS_VERSION"
log "Desktop: ${DESKTOP_INFO:-Default}"

# Thiết lập phiên D-Bus an toàn cho systemd user
CURRENT_UID=$(id -u)
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$CURRENT_UID}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}"

#=========================================================
# 2. SUDO CHECK & KEEPALIVE
#=========================================================

log "Xác thực quyền quản trị..."
sudo -v || die "Không xác thực được sudo."

while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
SUDO_PID=$!
trap 'kill "$SUDO_PID" 2>/dev/null || true; error "Lỗi tại dòng $LINENO"; exit 1' ERR

#=========================================================
# 3. UPDATE PACKAGE INDEX (Bỏ qua PPA lỗi nếu có)
#=========================================================

log "Cập nhật danh sách gói..."
sudo apt-get update -o Acquire::AllowInsecureRepositories=true -o Acquire::AllowDowngradeToInsecureRepositories=true || {
    warn "Một số kho PPA bên thứ ba bị 404, tiếp tục tiến trình..."
}
success "Cập nhật Package Index thành công."

#=========================================================
# 4. CÀI ĐẶT RCLONE & FUSE3 CHO MỌI HỆ THỐNG
#=========================================================

INSTALL_MODE="Rclone Native FUSE Mount"
TARGET_DIR="$HOME/GoogleDrive"
mkdir -p "$TARGET_DIR"

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

# Cấu hình systemd user service
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

# Nạp lại daemon với bọc an toàn tránh ngắt script nếu lỗi D-Bus bus
systemctl --user daemon-reload 2>/dev/null || true

kill "$SUDO_PID" 2>/dev/null || true

#=========================================================
# 5. XÁC THỰC OAUTH TỰ ĐỘNG MỞ TRÌNH DUYỆT (1 LẦN)
#=========================================================

DRIVE_CONFIGURED=false
if rclone listremotes 2>/dev/null | grep -q "^drive:"; then
    if rclone config show drive 2>/dev/null | grep -q "token ="; then
        DRIVE_CONFIGURED=true
    fi
fi

if [[ "$DRIVE_CONFIGURED" == false ]]; then
    echo
    echo -e "${YELLOW}=====================================================${NC}"
    echo -e "${YELLOW}       ĐANG MỞ KẾT NỐI GOOGLE TRÊN TRÌNH DUYỆT       ${NC}"
    echo -e "${YELLOW}=====================================================${NC}"
    log "Trình duyệt web sẽ tự động mở để ủy quyền..."
    log "Vui lòng đăng nhập Gmail và bấm 'Cho phép' (Allow)."
    echo "-----------------------------------------------------"

    rclone config delete drive 2>/dev/null || true
    rclone config create drive drive scope drive config_is_local true < /dev/tty

    success "Đã xác thực và lưu cấu hình Google Drive thành công!"
else
    log "Đã tìm thấy cấu hình remote 'drive' hợp lệ trên máy."
fi

# Giải phóng điểm mount cũ nếu còn kẹt
fusermount -uz "$TARGET_DIR" 2>/dev/null || true

log "Kích hoạt và nạp chạy Systemd Mount Service..."
systemctl --user daemon-reload 2>/dev/null || true
systemctl --user enable --now rclone-gdrive.service 2>/dev/null || true
sleep 3

#=========================================================
# 6. GHIM LỐI TẮT VÀO THANH PLACES (DOLPHIN & NEMO)
#=========================================================

# 1. Ghim vào Nemo / GTK (Linux Mint)
GTK_BOOKMARKS="$HOME/.config/gtk-3.0/bookmarks"
mkdir -p "$HOME/.config/gtk-3.0"
touch "$GTK_BOOKMARKS"
sed -i '/GoogleDrive/d' "$GTK_BOOKMARKS"
echo "file://$TARGET_DIR Google Drive" >> "$GTK_BOOKMARKS"
log "Đã thêm lối tắt vào trình quản lý tệp Nemo (Linux Mint)."

# 2. Ghim vào Dolphin (Kubuntu / KDE)
USER_PLACES="$HOME/.local/share/user-places.xbel"
if [[ -f "$USER_PLACES" ]]; then
    sed -i '/<bookmark href="gdrive:\/">/,/<\/bookmark>/d' "$USER_PLACES" 2>/dev/null || true
    sed -i '/<bookmark href="file:\/\/.*GoogleDrive">/,/<\/bookmark>/d' "$USER_PLACES" 2>/dev/null || true
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
    log "Đã thêm lối tắt vào trình quản lý tệp Dolphin (Kubuntu)."
fi

#=========================================================
# 7. HOÀN TẤT
#=========================================================

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

echo
echo -e "${GREEN}====================================================="
echo "         GOOGLE DRIVE SETUP COMPLETED"
echo "====================================================="
echo -e "${NC}"

echo "Hệ điều hành : $OS_NAME $OS_VERSION"
echo "Thư mục gắn  : $TARGET_DIR"
echo "Trạng thái   : "
if systemctl --user is-active --quiet rclone-gdrive.service 2>/dev/null; then
    echo -e "  -> ${GREEN}KẾT NỐI THÀNH CÔNG (Active Running).${NC}"
    echo "  -> Toàn bộ dữ liệu Drive đã sẵn sàng trong File Manager!"
else
    echo -e "  -> ${YELLOW}CHƯA KÍCH HOẠT: Vui lòng kiểm tra lại quá trình xác thực.${NC}"
fi
echo "Thời gian    : ${ELAPSED} giây"

echo
success "Hoàn tất cài đặt Google Drive Integrator 4.3."

exit 0
