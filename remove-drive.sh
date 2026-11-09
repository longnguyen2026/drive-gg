#!/usr/bin/env bash
#=========================================================
# Google Drive Clean & Reset Tool
# Linux Mint / Kubuntu / Ubuntu KDE
# Author  : Long Nguyen
# Script  : uninstall-google-drive.sh
# Version : 1.0 ngày 09.11.2026
#=========================================================

set -Eeuo pipefail

SCRIPT_NAME="$(basename "$0")"

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
echo "       GOOGLE DRIVE CLEAN & RESET UTILITY"
echo "       Dọn sạch kết nối Rclone & KDE KIO GDrive"
echo "       Author: Long Nguyen"
echo "====================================================="
echo -e "${NC}"

[[ $EUID -ne 0 ]] || die \
"Không chạy script bằng root/sudo trực tiếp!
Hãy chạy: bash $SCRIPT_NAME"

#=========================================================
# 1. DỪNG VÀ GỠ BỎ SYSTEMD USER SERVICE
#=========================================================

log "Dừng và hủy kích hoạt Systemd User Service..."

systemctl --user stop rclone-gdrive.service 2>/dev/null || true
systemctl --user disable rclone-gdrive.service 2>/dev/null || true

SERVICE_FILE="$HOME/.config/systemd/user/rclone-gdrive.service"
if [[ -f "$SERVICE_FILE" ]]; then
    rm -f "$SERVICE_FILE"
    systemctl --user daemon-reload
    success "Đã xóa file service rclone-gdrive.service."
fi

#=========================================================
# 2. NGẮT KẾT NỐI VÀ DỌN DẸP TIẾN TRÌNH MOUNT
#=========================================================

log "Ngắt kết nối điểm mount và dừng tiến trình chạy ngầm..."

fusermount -uz "$HOME/GoogleDrive" 2>/dev/null || true
killall rclone 2>/dev/null || true
killall kio_gdrive 2>/dev/null || true

success "Đã giải phóng điểm mount ~/GoogleDrive."

#=========================================================
# 3. XÓA CẤU HÌNH RCLONE & TOKEN DRIVE
#=========================================================

log "Xóa tài khoản Google Drive trong Rclone..."

if command -v rclone >/dev/null 2>&1; then
    rclone config delete drive 2>/dev/null || true
fi

rm -rf "$HOME/.config/rclone"
rm -rf "$HOME/.cache/rclone"

success "Đã dọn dẹp thư mục cấu hình và cache Rclone."

#=========================================================
# 4. XÓA CẤU HÌNH KDE KACCOUNTS & KIO CACHE
#=========================================================

log "Dọn dẹp cấu hình KAccounts và cache KIO..."

rm -f "$HOME/.local/share/accounts/providers/kde/google.provider"
rm -rf "$HOME/.local/share/accounts"

kbuildsycoca6 >/dev/null 2>&1 || kbuildsycoca5 >/dev/null 2>&1 || true

success "Đã làm mới lại cơ sở dữ liệu KIO."

#=========================================================
# 5. XÓA THƯ MỤC MOUNT VÀ BOOKMARK DOLPHIN
#=========================================================

log "Dọn dẹp thư mục ~/GoogleDrive và bookmark Places..."

rm -rf "$HOME/GoogleDrive"

USER_PLACES="$HOME/.local/share/user-places.xbel"
if [[ -f "$USER_PLACES" ]]; then
    sed -i '/<bookmark href="file:\/\/.*GoogleDrive">/,/<\/bookmark>/d' "$USER_PLACES"
    success "Đã gỡ bookmark Google Drive khỏi danh sách Places của Dolphin."
fi

#=========================================================
# 6. HOÀN TẤT
#=========================================================

echo
echo -e "${GREEN}====================================================="
echo "       DỌN DẸP TOÀN BỘ KẾT NỐI HOÀN TẤT!"
echo "====================================================="
echo -e "${NC}"

echo "Tất cả mount, service, token cũ và bookmark đã được đưa về trạng thái trắng."
echo "Hệ thống sẵn sàng để test lại script cài đặt mới."

exit 0
