#!/usr/bin/env bash
# =============================================================================
#  Backhaul Auto Installer / Manager
#  Fork    : https://github.com/ParvaneZone/BH_Parv
#  Upstream: https://github.com/Musixal/Backhaul  (binary releases pulled from here)
#  Usage   : sudo bash backhaul.sh
# =============================================================================
set -o pipefail

# ---------------------------- Colors / helpers ------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

msg()   { echo -e "${GREEN}[+]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
err()   { echo -e "${RED}[-]${NC} $1"; }
title() { echo -e "\n${CYAN}${BOLD}== $1 ==${NC}"; }
ask()   { # ask "prompt" default_value -> echoes result
    local prompt="$1" def="$2" ans
    if [[ -n "$def" ]]; then
        read -rp "$(echo -e "${BLUE}?${NC} ${prompt} [${def}]: ")" ans
        echo "${ans:-$def}"
    else
        read -rp "$(echo -e "${BLUE}?${NC} ${prompt}: ")" ans
        echo "$ans"
    fi
}
confirm() { # confirm "prompt" default(y/n) -> returns 0/1
    local prompt="$1" def="${2:-y}" ans
    local hint="y/N"; [[ "$def" == "y" ]] && hint="Y/n"
    read -rp "$(echo -e "${BLUE}?${NC} ${prompt} [${hint}]: ")" ans
    ans="${ans:-$def}"
    [[ "$ans" =~ ^[Yy]$ ]]
}

# ---------------------------- Constants --------------------------------------
REPO="Musixal/Backhaul"
INSTALL_DIR="/opt/backhaul"
CONFIG_DIR="/etc/backhaul"
BIN_PATH="${INSTALL_DIR}/backhaul"
SERVICE_NAME="backhaul"
SERVICE_PATH="/etc/systemd/system/${SERVICE_NAME}.service"
STATE_FILE="${CONFIG_DIR}/.install_state"

# ---------------------------- Root check --------------------------------------
if [[ $EUID -ne 0 ]]; then
    err "این اسکریپت باید با دسترسی root اجرا شود. مثال: sudo bash $0"
    exit 1
fi

# ---------------------------- Arch / OS detection ------------------------------
detect_arch() {
    local m; m="$(uname -m)"
    case "$m" in
        x86_64|amd64)   echo "amd64" ;;
        aarch64|arm64)  echo "arm64" ;;
        armv7l|armv7)   echo "armv7" ;;
        armv6l)         echo "armv6" ;;
        i386|i686)      echo "386" ;;
        *) err "معماری پشتیبانی‌نشده: $m"; exit 1 ;;
    esac
}

detect_pkg_mgr() {
    if command -v apt-get >/dev/null 2>&1; then echo "apt"
    elif command -v dnf >/dev/null 2>&1; then echo "dnf"
    elif command -v yum >/dev/null 2>&1; then echo "yum"
    elif command -v apk >/dev/null 2>&1; then echo "apk"
    else echo "unknown"
    fi
}

# ---------------------------- Dependencies ------------------------------------
install_dependencies() {
    title "بررسی و نصب پیش‌نیازها"
    local need=()
    for c in curl tar openssl; do
        command -v "$c" >/dev/null 2>&1 || need+=("$c")
    done
    if [[ ${#need[@]} -eq 0 ]]; then
        msg "همه پیش‌نیازها (curl, tar, openssl) از قبل نصب هستند."
        return
    fi
    local pm; pm="$(detect_pkg_mgr)"
    msg "در حال نصب: ${need[*]} (via $pm)"
    case "$pm" in
        apt) apt-get update -qq && apt-get install -y -qq "${need[@]}" ;;
        dnf) dnf install -y -q "${need[@]}" ;;
        yum) yum install -y -q "${need[@]}" ;;
        apk) apk add --quiet "${need[@]}" ;;
        *) err "نتوانستم مدیر بسته را تشخیص دهم. لطفاً ${need[*]} را دستی نصب کنید."; exit 1 ;;
    esac
}

# ---------------------------- Download & install binary ------------------------
fetch_latest_tag() {
    curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
        | grep -m1 '"tag_name"' | sed -E 's/.*"tag_name":\s*"([^"]+)".*/\1/'
}

download_backhaul() {
    title "دانلود آخرین نسخه‌ی Backhaul"
    local arch tag ver asset url tmp
    arch="$(detect_arch)"
    msg "معماری تشخیص داده‌شده: $arch"

    tag="$(fetch_latest_tag)"
    if [[ -z "$tag" ]]; then
        err "دریافت آخرین نسخه از GitHub API ناموفق بود (شاید ریت‌لیمیت یا مشکل شبکه)."
        tag="$(ask "برچسب نسخه را دستی وارد کنید (مثال: v0.7.2)" "")"
        [[ -z "$tag" ]] && { err "نسخه مشخص نشد. خروج."; exit 1; }
    fi
    ver="${tag#v}"
    msg "آخرین نسخه: $tag"

    tmp="$(mktemp -d)"
    # Try a set of common asset name patterns used by the goreleaser config of this project
    local candidates=(
        "backhaul_linux_${arch}.tar.gz"
        "backhaul_linux_${arch}_${ver}.tar.gz"
        "backhaul_${ver}_linux_${arch}.tar.gz"
        "backhaul-linux-${arch}.tar.gz"
    )

    mkdir -p "$tmp"
    local ok=""
    for name in "${candidates[@]}"; do
        url="https://github.com/${REPO}/releases/download/${tag}/${name}"
        if curl -fsSL -o "${tmp}/backhaul.tar.gz" "$url" 2>/dev/null; then
            ok="$name"
            break
        fi
    done

    if [[ -z "$ok" ]]; then
        warn "نام فایل استاندارد پیدا نشد؛ در حال جست‌وجوی خودکار در لیست asset های ریلیز..."
        local api_json; api_json="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/tags/${tag}")"
        local match
        match="$(echo "$api_json" | grep -oE '"browser_download_url":\s*"[^"]+"' \
                 | sed -E 's/.*"(https:[^"]+)"/\1/' \
                 | grep -i "linux" | grep -i "$arch" | head -n1)"
        if [[ -n "$match" ]]; then
            curl -fsSL -o "${tmp}/backhaul.tar.gz" "$match" || { err "دانلود از $match ناموفق بود."; exit 1; }
            ok="matched"
        else
            err "هیچ asset مناسبی برای معماری $arch در ریلیز $tag پیدا نشد."
            err "لطفاً به صورت دستی از اینجا دانلود کنید: https://github.com/${REPO}/releases/tag/${tag}"
            exit 1
        fi
    fi

    msg "استخراج بایاری..."
    mkdir -p "$INSTALL_DIR"
    tar -xzf "${tmp}/backhaul.tar.gz" -C "$tmp"
    local bin
    bin="$(find "$tmp" -maxdepth 2 -type f -iname 'backhaul*' ! -name '*.tar.gz' | head -n1)"
    if [[ -z "$bin" ]]; then
        err "باینری backhaul در آرشیو پیدا نشد."
        exit 1
    fi
    install -m 0755 "$bin" "$BIN_PATH"
    rm -rf "$tmp"
    echo "$tag" > "${CONFIG_DIR}/.version"
    msg "Backhaul $tag با موفقیت در ${BIN_PATH} نصب شد."
}

# ---------------------------- Utility generators --------------------------------
gen_token() { openssl rand -hex 16; }

gen_tls_cert() {
    local cn="$1" days="${2:-825}"
    mkdir -p "${CONFIG_DIR}/tls"
    openssl req -x509 -nodes -newkey rsa:2048 \
        -keyout "${CONFIG_DIR}/tls/server.key" \
        -out "${CONFIG_DIR}/tls/server.crt" \
        -days "$days" \
        -subj "/CN=${cn}" >/dev/null 2>&1
    msg "گواهی TLS ساخته شد: ${CONFIG_DIR}/tls/server.crt / server.key"
}

# ---------------------------- Interactive config builder ------------------------
declare -A CFG

pick_transport() {
    echo -e "\n${CYAN}پروتکل تونل را انتخاب کنید:${NC}"
    local opts=(tcp tcpmux udp ws wss wsmux wssmux)
    local i=1
    for o in "${opts[@]}"; do echo "  $i) $o"; ((i++)); done
    local sel
    while true; do
        sel="$(ask "شماره را وارد کنید" "1")"
        if [[ "$sel" =~ ^[1-7]$ ]]; then
            echo "${opts[$((sel-1))]}"
            return
        fi
        warn "عدد بین 1 تا 7 وارد کنید."
    done
}

build_server_config() {
    title "پیکربندی سرور (روی سروری که IP آن برای کاربر/سرویس در دسترس است، معمولاً خارج از ایران)"

    local transport bind_port token web_port sniffer log_level ports_input ports_toml
    transport="$(pick_transport)"
    bind_port="$(ask "پورت listen سرور (برای ارتباط بین سرور و کلاینت)" "3080")"
    token="$(ask "توکن احراز هویت (خالی بگذارید تا خودکار ساخته شود)" "")"
    [[ -z "$token" ]] && { token="$(gen_token)"; msg "توکن خودکار ساخته شد: $token"; }

    echo -e "\n${YELLOW}حالا پورت‌هایی که می‌خواهید از این سرور به سمت مقصد فوروارد شوند را مشخص کنید.${NC}"
    echo "مثال‌ها (هر خط را با کاما جدا کنید):"
    echo '  443,2053,8080                -> فوروارد این پورت‌ها به همان پورت روی کلاینت'
    echo '  8080=2087                    -> پورت لوکال 8080 را به پورت 2087 کلاینت بفرست'
    echo '  4000-4010                    -> بازه پورت'
    ports_input="$(ask "لیست پورت‌ها (کاما جدا)" "443")"
    IFS=',' read -ra parr <<< "$ports_input"
    ports_toml="ports = ["
    local first=1
    for p in "${parr[@]}"; do
        p="$(echo "$p" | xargs)"
        [[ -z "$p" ]] && continue
        [[ $first -eq 0 ]] && ports_toml+=","
        ports_toml+=$'\n    "'"$p"'",'
        first=0
    done
    ports_toml+=$'\n]'

    web_port="$(ask "پورت وب اینترفیس مانیتورینگ (0 برای غیرفعال)" "2060")"
    sniffer="false"; confirm "لاگ ترافیک (sniffer) فعال شود؟" "n" && sniffer="true"
    log_level="$(ask "سطح لاگ (panic/fatal/error/warn/info/debug/trace)" "info")"

    local tls_lines=""
    if [[ "$transport" == "wss" || "$transport" == "wssmux" ]]; then
        title "تنظیمات TLS (برای $transport لازم است)"
        if confirm "گواهی TLS خودکار (self-signed) ساخته شود؟" "y"; then
            local cn; cn="$(ask "دامنه یا IP سرور برای گواهی (CN)" "$(curl -s -4 ifconfig.me 2>/dev/null || echo example.com)")"
            gen_tls_cert "$cn"
            tls_lines=$'tls_cert = "'"${CONFIG_DIR}/tls/server.crt"$'"\ntls_key = "'"${CONFIG_DIR}/tls/server.key"$'"'
        else
            local cert key
            cert="$(ask "مسیر فایل tls_cert" "/root/server.crt")"
            key="$(ask "مسیر فایل tls_key" "/root/server.key")"
            tls_lines=$'tls_cert = "'"$cert"$'"\ntls_key = "'"$key"$'"'
        fi
    fi

    local mux_lines=""
    if [[ "$transport" == "tcpmux" || "$transport" == "wsmux" || "$transport" == "wssmux" ]]; then
        mux_lines=$'mux_con = 8\nmux_version = 1\nmux_framesize = 32768\nmux_recievebuffer = 4194304\nmux_streambuffer = 65536'
    fi

    mkdir -p "$CONFIG_DIR"
    {
        echo "[server]"
        echo "bind_addr = \"0.0.0.0:${bind_port}\""
        echo "transport = \"${transport}\""
        echo "token = \"${token}\""
        echo "keepalive_period = 75"
        echo "nodelay = true"
        echo "heartbeat = 40"
        echo "channel_size = 2048"
        [[ -n "$mux_lines" ]] && echo "$mux_lines"
        echo "sniffer = ${sniffer}"
        echo "web_port = ${web_port}"
        echo "sniffer_log = \"${CONFIG_DIR}/backhaul.json\""
        [[ -n "$tls_lines" ]] && echo "$tls_lines"
        echo "log_level = \"${log_level}\""
        echo ""
        echo "$ports_toml"
    } > "${CONFIG_DIR}/config.toml"

    msg "فایل کانفیگ ساخته شد: ${CONFIG_DIR}/config.toml"
    warn "این توکن را روی کلاینت هم دقیقاً همین‌طور وارد کنید: ${token}"
}

build_client_config() {
    title "پیکربندی کلاینت (روی سروری که پشت NAT/فیلترینگ است، معمولاً داخل ایران)"

    local transport remote_addr token edge_ip web_port sniffer log_level pool
    transport="$(pick_transport)"
    remote_addr="$(ask "آدرس و پورت سرور (IP_SERVER:PORT)" "")"
    while [[ -z "$remote_addr" ]]; do
        warn "این فیلد الزامی است."
        remote_addr="$(ask "آدرس و پورت سرور (IP_SERVER:PORT)" "")"
    done
    token="$(ask "توکن احراز هویت (باید دقیقاً مثل سرور باشد)" "")"
    while [[ -z "$token" ]]; do
        warn "توکن الزامی است و باید با سرور یکسان باشد."
        token="$(ask "توکن احراز هویت" "")"
    done

    edge_ip=""
    if [[ "$transport" == ws* || "$transport" == wss* ]]; then
        confirm "از edge_ip برای اتصال از طریق CDN استفاده می‌کنید؟" "n" && \
            edge_ip="$(ask "Edge IP" "")"
    fi

    pool="$(ask "تعداد کانکشن‌های از پیش برقرارشده (connection_pool)" "8")"
    web_port="$(ask "پورت وب اینترفیس مانیتورینگ (0 برای غیرفعال)" "2060")"
    sniffer="false"; confirm "لاگ ترافیک (sniffer) فعال شود؟" "n" && sniffer="true"
    log_level="$(ask "سطح لاگ (panic/fatal/error/warn/info/debug/trace)" "info")"

    local mux_lines=""
    if [[ "$transport" == "tcpmux" || "$transport" == "wsmux" || "$transport" == "wssmux" ]]; then
        mux_lines=$'mux_version = 1\nmux_framesize = 32768\nmux_recievebuffer = 4194304\nmux_streambuffer = 65536'
    fi

    mkdir -p "$CONFIG_DIR"
    {
        echo "[client]"
        echo "remote_addr = \"${remote_addr}\""
        [[ -n "$edge_ip" ]] && echo "edge_ip = \"${edge_ip}\""
        echo "transport = \"${transport}\""
        echo "token = \"${token}\""
        echo "connection_pool = ${pool}"
        echo "aggressive_pool = false"
        echo "keepalive_period = 75"
        echo "nodelay = true"
        echo "retry_interval = 3"
        echo "dial_timeout = 10"
        [[ -n "$mux_lines" ]] && echo "$mux_lines"
        echo "sniffer = ${sniffer}"
        echo "web_port = ${web_port}"
        echo "sniffer_log = \"${CONFIG_DIR}/backhaul.json\""
        echo "log_level = \"${log_level}\""
    } > "${CONFIG_DIR}/config.toml"

    msg "فایل کانفیگ ساخته شد: ${CONFIG_DIR}/config.toml"
}

# ---------------------------- systemd service -----------------------------------
install_service() {
    title "ساخت سرویس systemd"
    cat > "$SERVICE_PATH" <<EOF
[Unit]
Description=Backhaul Reverse Tunnel Service
After=network.target

[Service]
Type=simple
ExecStart=${BIN_PATH} -c ${CONFIG_DIR}/config.toml
Restart=always
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable "${SERVICE_NAME}" >/dev/null 2>&1
    systemctl restart "${SERVICE_NAME}"
    sleep 1
    if systemctl is-active --quiet "${SERVICE_NAME}"; then
        msg "سرویس ${SERVICE_NAME} فعال و در حال اجراست."
    else
        err "سرویس بالا نیامد. لاگ‌ها را بررسی کنید: journalctl -u ${SERVICE_NAME} -e -n 50"
    fi
}

show_status() {
    title "وضعیت سرویس"
    systemctl status "${SERVICE_NAME}" --no-pager -l || true
    echo
    if [[ -f "${CONFIG_DIR}/config.toml" ]]; then
        echo -e "${CYAN}--- config.toml ---${NC}"
        cat "${CONFIG_DIR}/config.toml"
    fi
}

show_logs() {
    journalctl -u "${SERVICE_NAME}" -e -n 100 --no-pager
}

uninstall_all() {
    title "حذف کامل Backhaul"
    if confirm "مطمئن هستید؟ این کار سرویس، باینری و کانفیگ را حذف می‌کند" "n"; then
        systemctl stop "${SERVICE_NAME}" 2>/dev/null
        systemctl disable "${SERVICE_NAME}" 2>/dev/null
        rm -f "$SERVICE_PATH"
        systemctl daemon-reload
        rm -rf "$INSTALL_DIR" "$CONFIG_DIR"
        msg "Backhaul به‌طور کامل حذف شد."
    else
        warn "لغو شد."
    fi
}

edit_config() {
    "${EDITOR:-nano}" "${CONFIG_DIR}/config.toml"
    systemctl restart "${SERVICE_NAME}"
    msg "کانفیگ ذخیره شد و سرویس ری‌استارت شد."
}

# ---------------------------- Main flow -----------------------------------------
do_install() {
    install_dependencies
    download_backhaul

    echo -e "\n${CYAN}این نود چه نقشی دارد؟${NC}"
    echo "  1) سرور (Server) - معمولاً خارج از ایران، IP قابل دسترس"
    echo "  2) کلاینت (Client) - پشت NAT/فیلترینگ، معمولاً داخل ایران"
    local role
    while true; do
        role="$(ask "انتخاب کنید (1 یا 2)" "1")"
        [[ "$role" == "1" || "$role" == "2" ]] && break
        warn "فقط 1 یا 2 را وارد کنید."
    done

    if [[ "$role" == "1" ]]; then
        build_server_config
    else
        build_client_config
    fi

    install_service
    title "نصب کامل شد ✅"
    echo -e "بررسی وضعیت:   ${BOLD}systemctl status ${SERVICE_NAME}${NC}"
    echo -e "دیدن لاگ زنده:  ${BOLD}journalctl -u ${SERVICE_NAME} -f${NC}"
    echo -e "ویرایش کانفیگ:  ${BOLD}bash $0${NC} و گزینه‌ی ویرایش را بزنید"
}

main_menu() {
    while true; do
        echo -e "\n${BOLD}${CYAN}=== Backhaul Manager ===${NC}"
        if [[ -x "$BIN_PATH" ]]; then
            echo -e "وضعیت نصب: ${GREEN}نصب شده${NC} ($(cat "${CONFIG_DIR}/.version" 2>/dev/null))"
        else
            echo -e "وضعیت نصب: ${YELLOW}نصب نشده${NC}"
        fi
        echo "1) نصب / پیکربندی مجدد (Install / Reconfigure)"
        echo "2) وضعیت سرویس و کانفیگ فعلی (Status)"
        echo "3) مشاهده لاگ زنده (Logs)"
        echo "4) ویرایش دستی کانفیگ (Edit config)"
        echo "5) ری‌استارت سرویس (Restart)"
        echo "6) حذف کامل (Uninstall)"
        echo "0) خروج (Exit)"
        local c; c="$(ask "انتخاب شما" "1")"
        case "$c" in
            1) do_install ;;
            2) show_status ;;
            3) show_logs ;;
            4) edit_config ;;
            5) systemctl restart "${SERVICE_NAME}" && msg "ری‌استارت شد." ;;
            6) uninstall_all ;;
            0) exit 0 ;;
            *) warn "گزینه نامعتبر" ;;
        esac
    done
}

mkdir -p "$CONFIG_DIR"
main_menu
