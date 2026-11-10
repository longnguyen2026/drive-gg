#!/usr/bin/env bash
#=========================================================
# Google Drive Integrator for Linux Mint (Cinnamon)
# Method  : Rclone Native FUSE Mount + Nemo Bookmark
# Author  : Long Nguyen
# Script  : drive-mint.sh
# Version : 2.2 ngày 10.11.2026
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
echo "       GOOGLE DRIVE INTEGRATOR FOR LINUX MINT"
echo "           Rclone Native FUSE (Nemo Places)"
echo "                 Author: Long Nguyen"
echo "====================================================="
echo -e "${NC}"

#=========================================================
# 1. KIỂM TRA MÔI TRƯỜNG & TỰ ĐỘNG BẮT DISPLAY / GUI SESSION
#=========================================================

[[ $EUID -ne 0 ]] || die \
"Không chạy script bằng root hoặc sudo trực tiếp!
Hãy chạy với quyền user thông thường: bash $SCRIPT_NAME"

CURRENT_USER="$USER"
CURRENT_UID="$(id -u)"
TARGET_DIR="$HOME/GoogleDrive"

# Tìm tài khoản người dùng đang đăng nhập trên màn hình desktop thực tế
ACTIVE_GUI_USER=$(who | awk '$0 ~ /(:0|\(:[0-9]\))/ {print $1; exit}' || true)
ACTIVE_GUI_USER="${ACTIVE_GUI_USER:-$CURRENT_USER}"

export DISPLAY=":0"

# Mượn quyền Xauthority của user đang sở hữu desktop
if [[ -f "/home/$ACTIVE_GUI_USER/.Xauthority" ]]; then
    export XAUTHORITY="/home/$ACTIVE_GUI_USER/.Xauthority"
else
    export XAUTHORITY="$HOME/.Xauthority"
fi

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$CURRENT_UID}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}"
export XDG_CURRENT_DESKTOP="${XDG_CURRENT_DESKTOP:-X-Cinnamon}"

# Cấp phép cho tiến trình mở cửa sổ GUI lên màn hình
xhost +local: 2>/dev/null || true
xhost +si:localuser:"$CURRENT_USER" 2>/dev/null || true

# Nhận diện trình duyệt sẵn có trên hệ thống để Rclone gọi chính xác
if command -v google-chrome >/dev/null 2>&1; then
    export BROWSER="google-chrome"
elif command -v microsoft-edge >/dev/null 2>&1; then
    export BROWSER="microsoft-edge"
elif command -v firefox >/dev/null 2>&1; then
    export BROWSER="firefox"
fi

log "User thực thi : $CURRENT_USER (GUI User: $ACTIVE_GUI_USER, DISPLAY: $DISPLAY)"
log "Trình duyệt   : ${BROWSER:-Mặc định hệ thống}"
log "Thư mục mount : $TARGET_DIR"

#=========================================================
# 2. XÁC THỰC QUYỀN SUDO & KEEPALIVE
#=========================================================

log "Xác thực quyền quản trị..."
sudo -v || die "Không xác thực được sudo."

while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
SUDO_PID=$!
trap 'kill "$SUDO_PID" 2>/dev/null || true; error "Lỗi tại dòng $LINENO"; exit 1' ERR

#=========================================================
# 3. CẬP NHẬT GÓI & CÀI ĐẶT RCLONE + FUSE3 + XDG-UTILS
#=========================================================

log "Cập nhật danh sách gói..."
sudo apt-get update -o Acquire::AllowInsecureRepositories=true -o Acquire::AllowDowngradeToInsecureRepositories=true || {
    warn "Bỏ qua cảnh báo repository để tiếp tục tiến trình..."
}

PACKAGES=(rclone fuse3 xdg-utils)
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
    log "Đang cài đặt các gói phụ thuộc..."
    sudo apt-get install -y "${MISSING_PACKAGES[@]}"
    success "Cài đặt gói thành công."
fi

kill "$SUDO_PID" 2>/dev/null || true

#=========================================================
# 4. THIẾT LẬP SYSTEMD USER SERVICE
#=========================================================

mkdir -p "$TARGET_DIR"
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

# Nạp lại systemd an toàn
systemctl --user daemon-reload 2>/dev/null || true

#=========================================================
# 5. XÁC THỰC OAUTH (TỰ ĐỘNG MỞ TRÌNH DUYỆT 1 LẦN DUY NHẤT)
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
    log "Trình duyệt web sẽ tự động mở lên màn hình desktop..."
    log "Vui lòng đăng nhập Gmail và bấm 'Cho phép' (Allow)."
    echo "-----------------------------------------------------"

    # Xóa remote drive cũ nếu lỗi/thiếu token
    rclone config delete drive 2>/dev/null || true

    # Khởi tạo remote và tự động bật trình duyệt
    rclone config create drive drive scope drive config_is_local true < /dev/tty

    success "Đã xác thực và lưu token Google Drive thành công!"
else
    log "Đã tìm thấy cấu hình remote 'drive' hợp lệ trên máy."
fi

# Giải phóng điểm mount cũ nếu bị kẹt FUSE
fusermount -uz "$TARGET_DIR" 2>/dev/null || true

#=========================================================
# 6. KHỞI CHẠY SERVICE VÀ GHIM BOOKMARK VÀO NEMO
#=========================================================

log "Kích hoạt Systemd Mount Service..."
systemctl --user daemon-reload 2>/dev/null || true
systemctl --user enable --now rclone-gdrive.service 2>/dev/null || true
sleep 3

# Ghim thư mục vào thanh Places bên trái của Nemo (GTK3 Bookmarks)
GTK_BOOKMARKS="$HOME/.config/gtk-3.0/bookmarks"
mkdir -p "$HOME/.config/gtk-3.0"
touch "$GTK_BOOKMARKS"

sed -i '/GoogleDrive/d' "$GTK_BOOKMARKS"
echo "file://$TARGET_DIR Google Drive" >> "$GTK_BOOKMARKS"
success "Đã ghim lối tắt Google Drive vào trình quản lý tệp Nemo."

#=========================================================
# 7. TỔNG KẾT
#=========================================================

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

echo
echo -e "${GREEN}====================================================="
echo "       CÀI ĐẶT GOOGLE DRIVE LINUX MINT HOÀN TẤT"
echo "====================================================="
echo -e "${NC}"

echo "Thư mục gắn  : $TARGET_DIR"
echo "Trạng thái   : "
if systemctl --user is-active --quiet rclone-gdrive.service 2>/dev/null; then
    echo -e "  -> ${GREEN}KẾT NỐI THÀNH CÔNG (Active Running).${NC}"
    echo "  -> Mở ứng dụng Nemo (Tập tin) -> Bấm vào mục 'Google Drive' ở cột trái để sử dụng."
else
    echo -e "  -> ${YELLOW}CHƯA KÍCH HOẠT: Vui lòng kiểm tra lại quyền xác thực trên trình duyệt.${NC}"
fi
echo "Thời gian    : ${ELAPSED} giây"
echo

exit 0
