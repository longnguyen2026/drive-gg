#!/usr/bin/env bash
#=========================================================
# Google Drive Integrator for Linux Mint (Cinnamon)
# Method  : Rclone Native FUSE Mount + Nemo Bookmark + Autostart
# Target  : Tự động phát hiện user Desktop thực tế (nhanvien)
# Author  : Long Nguyen
# Script  : drive-mint.sh
# Version : 3.1 ngày 10.11.2026
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
# 1. TỰ ĐỘNG XÁC ĐỊNH USER DESKTOP ĐÍCH (DESKTOP GUI USER)
#=========================================================

[[ $EUID -ne 0 ]] || die \
"Không chạy script bằng root hoặc sudo trực tiếp!
Hãy chạy với quyền user thông thường: bash $SCRIPT_NAME"

RUNNING_USER="$USER"

# Tự động phát hiện user đang thực sự ngồi trước màn hình Desktop Mint (:0)
ACTIVE_GUI_USER=$(who | awk '$0 ~ /(:0|\(:[0-9]\))/ {print $1; exit}' || true)
if [[ -z "$ACTIVE_GUI_USER" ]]; then
    ACTIVE_GUI_USER=$(loginctl list-sessions --no-legend 2>/dev/null | awk '{print $3}' | grep -v 'root' | head -n 1 || true)
fi

TARGET_USER="${ACTIVE_GUI_USER:-$RUNNING_USER}"
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
TARGET_UID=$(id -u "$TARGET_USER")
TARGET_DIR="$TARGET_HOME/GoogleDrive"

# Thiết lập môi trường hiển thị đồ họa
export DISPLAY=":0"
if [[ -f "$TARGET_HOME/.Xauthority" ]]; then
    export XAUTHORITY="$TARGET_HOME/.Xauthority"
else
    export XAUTHORITY="$HOME/.Xauthority"
fi

export XDG_RUNTIME_DIR="/run/user/$TARGET_UID"
export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
export XDG_CURRENT_DESKTOP="X-Cinnamon"

# Cấp quyền kết nối giao diện X11 cho mọi tiến trình nội bộ
xhost +local: 2>/dev/null || true
xhost +si:localuser:"$RUNNING_USER" 2>/dev/null || true
xhost +si:localuser:"$TARGET_USER" 2>/dev/null || true

# Tự động gán trình duyệt
if command -v google-chrome >/dev/null 2>&1; then
    export BROWSER="google-chrome"
elif command -v microsoft-edge >/dev/null 2>&1; then
    export BROWSER="microsoft-edge"
elif command -v firefox >/dev/null 2>&1; then
    export BROWSER="firefox"
fi

log "User điều khiển : $RUNNING_USER"
log "User đích       : $TARGET_USER (UID: $TARGET_UID)"
log "Thư mục mount   : $TARGET_DIR"

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
# 4. CHUẨN BỊ THƯ MỤC MOUNT VÀ CẤU HÌNH CHO TARGET_USER
#=========================================================

sudo mkdir -p "$TARGET_DIR" "$TARGET_HOME/.config/rclone" "$TARGET_HOME/.config/autostart" "$TARGET_HOME/.config/gtk-3.0"
sudo chown -R "$TARGET_USER:$TARGET_USER" "$TARGET_DIR" "$TARGET_HOME/.config/rclone" "$TARGET_HOME/.config/autostart" "$TARGET_HOME/.config/gtk-3.0"

# Nếu user đang chạy (it) đã có cấu hình rclone hợp lệ, đồng bộ ngay sang TARGET_USER
if [[ "$RUNNING_USER" != "$TARGET_USER" ]] && [[ -f "$HOME/.config/rclone/rclone.conf" ]]; then
    if grep -q "token =" "$HOME/.config/rclone/rclone.conf" 2>/dev/null; then
        sudo cp -f "$HOME/.config/rclone/rclone.conf" "$TARGET_HOME/.config/rclone/rclone.conf"
        sudo chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.config/rclone/rclone.conf"
        log "Đã đồng bộ file cấu hình token từ $RUNNING_USER sang $TARGET_USER."
    fi
fi

#=========================================================
# 5. XÁC THỰC OAUTH CHO TARGET_USER (NẾU CHƯA CÓ TOKEN)
#=========================================================

DRIVE_CONFIGURED=false
if sudo -u "$TARGET_USER" rclone listremotes 2>/dev/null | grep -q "^drive:"; then
    if sudo -u "$TARGET_USER" rclone config show drive 2>/dev/null | grep -q "token ="; then
        DRIVE_CONFIGURED=true
    fi
fi

if [[ "$DRIVE_CONFIGURED" == false ]]; then
    echo
    echo -e "${YELLOW}=====================================================${NC}"
    echo -e "${YELLOW}       ĐANG MỞ KẾT NỐI GOOGLE TRÊN TRÌNH DUYỆT       ${NC}"
    echo -e "${YELLOW}=====================================================${NC}"
    log "Trình duyệt web sẽ tự động mở lên màn hình desktop của $TARGET_USER..."
    log "Vui lòng đăng nhập Gmail và bấm 'Cho phép' (Allow)."
    echo "-----------------------------------------------------"

    sudo -u "$TARGET_USER" rclone config delete drive 2>/dev/null || true

    sudo -u "$TARGET_USER" \
        DISPLAY="$DISPLAY" \
        XAUTHORITY="$XAUTHORITY" \
        XDG_RUNTIME_DIR="/run/user/$TARGET_UID" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$TARGET_UID/bus" \
        BROWSER="${BROWSER:-}" \
        rclone config create drive drive scope drive config_is_local true < /dev/tty

    success "Đã xác thực và lưu token Google Drive thành công!"
else
    log "Đã có cấu hình remote 'drive' hợp lệ cho tài khoản $TARGET_USER."
fi

# Dọn dẹp điểm mount cũ nếu bị treo FUSE
sudo -u "$TARGET_USER" fusermount -uz "$TARGET_DIR" 2>/dev/null || true

#=========================================================
# 6. KHỞI CHẠY MOUNT VÀ THIẾT LẬP AUTOSTART + NEMO BOOKMARK
#=========================================================

log "Khởi chạy tiến trình mount ổ đĩa ngầm (Daemon)..."
sudo -u "$TARGET_USER" rclone mount drive: "$TARGET_DIR" \
  --vfs-cache-mode full \
  --vfs-cache-max-age 24h \
  --vfs-read-chunk-size 32M \
  --buffer-size 32M \
  --dir-cache-time 72h --daemon
sleep 2

# Tạo Autostart Desktop Entry (Bảo đảm luôn tự mount khi nhanvien đăng nhập vào máy)
AUTOSTART_FILE="$TARGET_HOME/.config/autostart/rclone-gdrive.desktop"
sudo -u "$TARGET_USER" tee "$AUTOSTART_FILE" > /dev/null <<EOF
[Desktop Entry]
Type=Application
Exec=/usr/bin/rclone mount drive: $TARGET_DIR --vfs-cache-mode full --daemon
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true#!/usr/bin/env bash
#=========================================================
# Google Drive Integrator for Linux Mint (Cinnamon)
# Method  : Rclone Native FUSE Mount + Nemo Bookmark
# Target  : Tự động phát hiện user Desktop (nhanvien) dù chạy qua IT/RustDesk
# Author  : Long Nguyen
# Script  : drive-mint.sh
# Version : 3.0 ngày 10.11.2026
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
# 1. TỰ ĐỘNG XÁC ĐỊNH USER DESKTOP ĐÍCH (DESKTOP GUI USER)
#=========================================================

[[ $EUID -ne 0 ]] || die \
"Không chạy script bằng root hoặc sudo trực tiếp!
Hãy chạy với quyền user thông thường: bash $SCRIPT_NAME"

RUNNING_USER="$USER"

# Phát hiện user đang thực sự ngồi trước màn hình Desktop Mint (:0)
ACTIVE_GUI_USER=$(who | awk '$0 ~ /(:0|\(:[0-9]\))/ {print $1; exit}' || true)
if [[ -z "$ACTIVE_GUI_USER" ]]; then
    ACTIVE_GUI_USER="$RUNNING_USER"
fi

TARGET_USER="$ACTIVE_GUI_USER"
TARGET_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)
TARGET_UID=$(id -u "$TARGET_USER")
TARGET_DIR="$TARGET_HOME/GoogleDrive"


Name=Mount Google Drive
Comment=Tu dong ket noi Google Drive khi dang nhap
EOF

# Ghim lối tắt vào Nemo Places (GTK 3.0 Bookmarks)
GTK_BOOKMARKS="$TARGET_HOME/.config/gtk-3.0/bookmarks"
sudo -u "$TARGET_USER" touch "$GTK_BOOKMARKS"
sudo -u "$TARGET_USER" sed -i '/GoogleDrive/d' "$GTK_BOOKMARKS"
echo "file://$TARGET_DIR Google Drive" | sudo -u "$TARGET_USER" tee -a "$GTK_BOOKMARKS" >/dev/null
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

echo "Tài khoản sở hữu : $TARGET_USER"
echo "Thư mục gắn      : $TARGET_DIR"
echo -n "Trạng thái       : "

if mountpoint -q "$TARGET_DIR"; then
    echo -e "${GREEN}KẾT NỐI THÀNH CÔNG (Mounted & Active).${NC}"
    echo "  -> Đã ghim vào thanh Devices/Bookmarks của Nemo!"
    echo "  -> Đã kích hoạt Autostart tự động chạy khi mở máy."
else
    echo -e "${YELLOW}Đang mount ngầm trong nền.${NC}"
fi

echo "Thời gian        : ${ELAPSED} giây"
echo

exit 0
