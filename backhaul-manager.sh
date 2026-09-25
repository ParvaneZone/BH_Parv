#!/usr/bin/env bash

set -o pipefail

ROOT="${BH_ROOT:-}"
BIN="$ROOT/usr/local/bin/backhaul"
CONF_DIR="$ROOT/etc/backhaul"
CERT_DIR="$CONF_DIR/certs"
SVC_DIR="$ROOT/etc/systemd/system"
SVC_PREFIX="backhaul-"
GH_REPO="Musixal/Backhaul"
CMD_NAME="ParvBH"
SELF_CMD="$ROOT/usr/local/bin/$CMD_NAME"
MY_REPO="https://github.com/ParvaneZone/BH_Parv"
MY_TELEGRAM="https://t.me/parv49e"
MY_NAME="Parv-BH | Backhaul Manager"

if [[ -t 1 ]]; then
  R=$'\e[31m'; G=$'\e[32m'; Y=$'\e[33m'; C=$'\e[36m'; BD=$'\e[1m'; N=$'\e[0m'
else
  R=; G=; Y=; C=; BD=; N=
fi
info() { echo -e "${C}[*]${N} $*"; }
ok()   { echo -e "${G}[+]${N} $*"; }
warn() { echo -e "${Y}[!]${N} $*"; }
err()  { echo -e "${R}[x]${N} $*" >&2; }

sd() { [[ -n $BH_NOSYSTEMD ]] && return 0; systemctl "$@"; }
is_active() { [[ -n $BH_NOSYSTEMD ]] && return 1; systemctl is-active --quiet "$SVC_PREFIX$1"; }

ask() {
  local p="$1" d="$2" v
  if [[ -n $d ]]; then read -r -p "$p [$d]: " v; v="${v:-$d}"; else read -r -p "$p: " v; fi
  printf '%s' "$v"
}
ask_yn() {
  local p="$1" d="${2:-y}" v hint="y/N"
  [[ $d == y ]] && hint="Y/n"
  read -r -p "$p [$hint]: " v
  v="${v:-$d}"
  [[ $v =~ ^[Yy] ]]
}
ask_int() {
  local v
  while true; do
    v=$(ask "$1" "$2")
    if [[ $v =~ ^[0-9]+$ ]] && (( v >= $3 && v <= $4 )); then echo "$v"; return; fi
    err "Enter a number between $3 and $4."
  done
}
choose() {
  local prompt="$1" def="$2"; shift 2
  local opts=("$@") i v
  for i in "${!opts[@]}"; do printf '  %d) %s\n' $((i + 1)) "${opts[$i]#*|}" >&2; done
  while true; do
    v=$(ask "$prompt" "$def")
    if [[ $v =~ ^[0-9]+$ ]] && (( v >= 1 && v <= ${#opts[@]} )); then
      echo "${opts[$((v - 1))]%%|*}"; return
    fi
    err "Choose a number between 1 and ${#opts[@]}."
  done
}
rand_token() { head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n'; }
valid_token() { local re='^[A-Za-z0-9._~@%^*+=:,/!-]+$'; [[ $1 =~ $re ]]; }

get_public_ip() {
  local ip
  ip=$(curl -4fsS --max-time 4 https://api.ipify.org 2>/dev/null) ||
  ip=$(curl -4fsS --max-time 4 https://ifconfig.me 2>/dev/null) ||
  ip=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}')
  printf '%s' "$ip"
}
detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64) echo amd64 ;;
    aarch64|arm64) echo arm64 ;;
    *) echo unknown ;;
  esac
}
ensure_deps() {
  local miss=() c
  for c in "$@"; do command -v "$c" >/dev/null 2>&1 || miss+=("$c"); done
  (( ${#miss[@]} == 0 )) && return 0
  info "Installing missing packages: ${miss[*]}"
  if command -v apt-get >/dev/null 2>&1; then apt-get update -qq && apt-get install -y -qq "${miss[@]}"
  elif command -v dnf >/dev/null 2>&1; then dnf install -y -q "${miss[@]}"
  elif command -v yum >/dev/null 2>&1; then yum install -y -q "${miss[@]}"
  else err "Please install manually: ${miss[*]}"; return 1
  fi
}

port_in_use() {
  command -v ss >/dev/null 2>&1 || return 1
  local flag="-lnt"; [[ ${2:-tcp} == udp ]] && flag="-lnu"
  ss "$flag" 2>/dev/null | awk '{print $4}' | grep -qE "[:.]${1}$"
}
conf_port_taken() {
  grep -qE "^(bind_addr[[:space:]]*=[[:space:]]*\".*:${1}\"|web_port[[:space:]]*=[[:space:]]*${1}[[:space:]]*$)" \
    "$CONF_DIR"/*.toml 2>/dev/null
}
next_free_port() {
  local p="$1"
  while port_in_use "$p" "${2:-tcp}" || conf_port_taken "$p"; do p=$((p + 1)); done
  echo "$p"
}
ask_tunnel_port() {
  local v
  while true; do
    v=$(ask_int "Tunnel port (the port the server listens on)" "$1" 1 65535)
    if port_in_use "$v" "$2"; then err "Port $v is already in use on this machine."; continue; fi
    if conf_port_taken "$v"; then err "Port $v is used by another tunnel."; continue; fi
    echo "$v"; return
  done
}
valid_spec() {
  local re='^([0-9]{1,3}(\.[0-9]{1,3}){3}:)?[0-9]{1,5}(-[0-9]{1,5})?((=|:)([A-Za-z0-9.-]+:)?[0-9]{1,5})?$'
  [[ $1 =~ $re ]]
}
ask_ports() {
  {
    echo "Ports to forward, comma separated. Examples:"
    echo "  443,8443        listen on 443 and 8443 -> same port on the other side"
    echo "  4000=5000       listen on 4000 -> forward to port 5000"
    echo "  443-600         a whole range"
    echo "  443=1.1.1.1:5201  forward to a specific IP:port"
  } >&2
  local v s arr bad
  while true; do
    v=$(ask "Ports" ""); v="${v// /}"
    [[ -z $v ]] && { err "At least one port is required."; continue; }
    IFS=',' read -ra arr <<<"$v"; bad=0
    for s in "${arr[@]}"; do valid_spec "$s" || { err "Invalid entry: $s"; bad=1; }; done
    (( bad )) && continue
    printf '%s\n' "${arr[@]}"; return
  done
}
spec_local() {
  local s="$1" l
  if [[ $s == *=* ]]; then l="${s%%=*}"
  elif [[ $s == *:* ]]; then l="${s%%:*}"
  else l="$s"; fi
  l="${l##*:}"
  if [[ $l == *.* ]]; then l="${s#*:}"; l="${l%%[=:]*}"; fi
  echo "${l/-/:}"
}

list_tunnels() {
  local f
  for f in "$CONF_DIR"/*.toml; do [[ -e $f ]] && basename "$f" .toml; done
}
cfg_get() {
  local line v
  line=$(grep -m1 -E "^$2[[:space:]]*=" "$CONF_DIR/$1.toml" 2>/dev/null) || return 1
  v="${line#*=}"; v="${v#"${v%%[![:space:]]*}"}"
  if [[ $v == \"* ]]; then v="${v#\"}"; v="${v%%\"*}"
  else v="${v%%#*}"; v="${v%"${v##*[![:space:]]}"}"; fi
  printf '%s' "$v"
}
cfg_role() { grep -qE '^\[server\]' "$CONF_DIR/$1.toml" 2>/dev/null && echo server || echo client; }
get_ports() {
  awk '/^ports[[:space:]]*=[[:space:]]*\[/{f=1;next} f&&/^\]/{f=0} f' "$CONF_DIR/$1.toml" | tr -d ' ",'
}
set_ports() {
  local n="$1"; shift
  local f="$CONF_DIR/$n.toml" tmp p
  tmp=$(mktemp)
  awk '/^ports[[:space:]]*=[[:space:]]*\[.*\]/{next}
       /^ports[[:space:]]*=[[:space:]]*\[/{s=1;next}
       s&&/^\]/{s=0;next}
       !s{print}' "$f" >"$tmp"
  {
    cat "$tmp"
    echo "ports = ["
    for p in "$@"; do echo "  \"$p\","; done
    echo "]"
  } >"$f"
  rm -f "$tmp"; chmod 600 "$f"
}
next_name() { local i=1; while [[ -e "$CONF_DIR/tunnel$i.toml" ]]; do i=$((i + 1)); done; echo "tunnel$i"; }
ask_name() {
  local v
  while true; do
    v=$(ask "Tunnel name (letters, digits, - _)" "$(next_name)")
    [[ $v =~ ^[A-Za-z0-9_-]{1,24}$ ]] || { err "Invalid name."; continue; }
    [[ -e "$CONF_DIR/$v.toml" ]] && { err "A tunnel named '$v' already exists."; continue; }
    echo "$v"; return
  done
}
ask_token() {
  local v d
  d=$(rand_token)
  while true; do
    v=$(ask "Token (must be identical on both sides)" "$d")
    valid_token "$v" && { echo "$v"; return; }
    err "Token may only contain letters, digits and . _ ~ @ % ^ * + = : , / ! -"
  done
}

reset_vars() {
  NAME=; TRANSPORT=tcp; TUN_PORT=; TOKEN=; PORTS=(); ACCEPT_UDP=false
  NODELAY=true; KEEPALIVE=75; HEARTBEAT=40; CHANNEL_SIZE=2048; WEB_PORT=0
  LOG_LEVEL=info; MUX_CON=8; MUX_VER=1; MUX_FRAME=32768; MUX_RECV=4194304
  MUX_STREAM=65536; POOL=8; AGGR=false; RETRY=3; DIAL=10; EDGE_IP=
  SRV_HOST=; SRV_PORT=
}
is_mux() { [[ $TRANSPORT == *mux ]]; }
is_tls() { [[ $TRANSPORT == wss || $TRANSPORT == wssmux ]]; }
is_ws()  { [[ $TRANSPORT == ws* ]]; }

ask_transport() {
  echo "Transport type:" >&2
  choose "Select" 1 \
    "tcp|tcp - simple and fast (good default)" \
    "tcpmux|tcpmux - many sessions over one TCP connection" \
    "udp|udp - UDP transport" \
    "ws|ws - WebSocket (passes HTTP-only firewalls / CDN)" \
    "wss|wss - WebSocket + TLS (encrypted)" \
    "wsmux|wsmux - WebSocket + multiplexing" \
    "wssmux|wssmux - WebSocket + TLS + multiplexing"
}
ask_mux_advanced() {
  MUX_CON=$(ask_int "mux_con (multiplexed connections)" "$MUX_CON" 1 1024)
  MUX_VER=$(ask_int "mux_version (1 or 2, must match on both sides)" "$MUX_VER" 1 2)
}

make_conn_string() {
  printf 'BH1:%s' "$(printf '%s|%s|%s|%s|%s' "$TRANSPORT" "$1" "$TUN_PORT" "$TOKEN" "$MUX_VER" | base64 | tr -d '\n')"
}
parse_conn_string() {
  local s="${1#BH1:}" d
  d=$(printf '%s' "$s" | base64 -d 2>/dev/null) || return 1
  IFS='|' read -r TRANSPORT SRV_HOST SRV_PORT TOKEN MUX_VER <<<"$d"
  [[ $TRANSPORT =~ ^(tcp|tcpmux|udp|ws|wss|wsmux|wssmux)$ ]] || return 1
  [[ -n $SRV_HOST && $SRV_PORT =~ ^[0-9]+$ && -n $TOKEN ]] || return 1
  MUX_VER="${MUX_VER:-1}"
}

write_server_conf() {
  local f="$CONF_DIR/$NAME.toml" p
  mkdir -p "$CONF_DIR"
  {
    echo "[server]"
    echo "bind_addr = \"0.0.0.0:${TUN_PORT}\""
    echo "transport = \"${TRANSPORT}\""
    echo "token = \"${TOKEN}\""
    echo "channel_size = ${CHANNEL_SIZE}"
    echo "heartbeat = ${HEARTBEAT}"
    if [[ $TRANSPORT != udp ]]; then
      echo "keepalive_period = ${KEEPALIVE}"
      echo "nodelay = ${NODELAY}"
    fi
    [[ $TRANSPORT == tcp ]] && echo "accept_udp = ${ACCEPT_UDP}"
    if is_mux; then
      echo "mux_con = ${MUX_CON}"
      echo "mux_version = ${MUX_VER}"
      echo "mux_framesize = ${MUX_FRAME}"
      echo "mux_recievebuffer = ${MUX_RECV}"
      echo "mux_streambuffer = ${MUX_STREAM}"
    fi
    if is_tls; then
      echo "tls_cert = \"${CERT_DIR#$ROOT}/${NAME}.crt\""
      echo "tls_key = \"${CERT_DIR#$ROOT}/${NAME}.key\""
    fi
    echo "sniffer = false"
    echo "web_port = ${WEB_PORT}"
    echo "log_level = \"${LOG_LEVEL}\""
    echo "ports = ["
    for p in "${PORTS[@]}"; do echo "  \"$p\","; done
    echo "]"
  } >"$f"
  chmod 600 "$f"
}
write_client_conf() {
  local f="$CONF_DIR/$NAME.toml" host="$SRV_HOST"
  [[ $host == *:* && $host != \[* ]] && host="[$host]"
  mkdir -p "$CONF_DIR"
  {
    echo "[client]"
    echo "remote_addr = \"${host}:${SRV_PORT}\""
    is_ws && [[ -n $EDGE_IP ]] && echo "edge_ip = \"${EDGE_IP}\""
    echo "transport = \"${TRANSPORT}\""
    echo "token = \"${TOKEN}\""
    echo "connection_pool = ${POOL}"
    echo "aggressive_pool = ${AGGR}"
    echo "retry_interval = ${RETRY}"
    if [[ $TRANSPORT != udp ]]; then
      echo "keepalive_period = ${KEEPALIVE}"
      echo "dial_timeout = ${DIAL}"
      echo "nodelay = ${NODELAY}"
    fi
    if is_mux; then
      echo "mux_version = ${MUX_VER}"
      echo "mux_framesize = ${MUX_FRAME}"
      echo "mux_recievebuffer = ${MUX_RECV}"
      echo "mux_streambuffer = ${MUX_STREAM}"
    fi
    echo "sniffer = false"
    echo "web_port = ${WEB_PORT}"
    echo "log_level = \"${LOG_LEVEL}\""
  } >"$f"
  chmod 600 "$f"
}
make_cert() {
  ensure_deps openssl || return 1
  mkdir -p "$CERT_DIR"
  openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$CERT_DIR/$1.key" -out "$CERT_DIR/$1.crt" \
    -subj "/CN=backhaul-$1" >/dev/null 2>&1 || { err "Certificate generation failed."; return 1; }
  chmod 600 "$CERT_DIR/$1.key"
  ok "Self-signed TLS certificate created for '$1'."
}

create_service() {
  local n="$1" desc="$2"
  mkdir -p "$SVC_DIR"
  cat >"$SVC_DIR/${SVC_PREFIX}${n}.service" <<EOF
[Unit]
Description=Backhaul ${desc}
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${BIN#$ROOT} -c ${CONF_DIR#$ROOT}/${n}.toml
Restart=always
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
  sd daemon-reload
  sd enable "${SVC_PREFIX}${n}" >/dev/null 2>&1
  sd restart "${SVC_PREFIX}${n}"
}
verify_start() {
  local n="$1"
  [[ -n $BH_NOSYSTEMD ]] && return 0
  sleep 2
  if is_active "$n"; then ok "Service ${SVC_PREFIX}${n} is running."
  else
    err "Service failed to start. Last log lines:"
    journalctl -u "${SVC_PREFIX}${n}" -n 15 --no-pager 2>/dev/null
    return 1
  fi
}

ufw_active() { command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; }
server_firewall() {
  ufw_active || return 0
  ask_yn "ufw is active. Open the tunnel port and forwarded ports?" y || return 0
  local tp=tcp fp="tcp" s p pr
  [[ $TRANSPORT == udp ]] && { tp=udp; fp="udp"; }
  [[ $TRANSPORT == tcp && $ACCEPT_UDP == true ]] && fp="tcp udp"
  ufw allow "${TUN_PORT}/${tp}" >/dev/null
  for s in "${PORTS[@]}"; do
    p=$(spec_local "$s")
    for pr in $fp; do ufw allow "${p}/${pr}" >/dev/null; done
  done
  ok "ufw rules added."
}

install_binary() {
  ensure_deps curl tar || return 1
  mkdir -p "$(dirname "$BIN")"
  local arch choice tmp url file bin
  arch=$(detect_arch)
  echo "Install Backhaul from:"
  choice=$(choose "Select" 1 \
    "gh|GitHub latest release (needs access to github.com)" \
    "url|Custom URL / mirror (.tar.gz or raw binary)" \
    "file|Local file on this machine (.tar.gz or raw binary)" \
    "src|Build from source (needs git and Go >= 1.23.1)")
  tmp=$(mktemp -d)
  case "$choice" in
    gh)
      [[ $arch == unknown ]] && { err "Unsupported CPU: $(uname -m). Use another option."; rm -rf "$tmp"; return 1; }
      url="https://github.com/${GH_REPO}/releases/latest/download/backhaul_linux_${arch}.tar.gz"
      info "Downloading $url"
      curl -fL --retry 3 --connect-timeout 15 -o "$tmp/pkg" "$url" || { err "Download failed."; rm -rf "$tmp"; return 1; }
      ;;
    url)
      url=$(ask "URL" "")
      [[ -z $url ]] && { rm -rf "$tmp"; return 1; }
      curl -fL --retry 3 --connect-timeout 15 -o "$tmp/pkg" "$url" || { err "Download failed."; rm -rf "$tmp"; return 1; }
      ;;
    file)
      file=$(ask "Path to file" "")
      [[ -f $file ]] || { err "File not found."; rm -rf "$tmp"; return 1; }
      cp "$file" "$tmp/pkg"
      ;;
    src)
      command -v git >/dev/null 2>&1 && command -v go >/dev/null 2>&1 || { err "git and go are required."; rm -rf "$tmp"; return 1; }
      git clone --depth 1 "https://github.com/${GH_REPO}.git" "$tmp/src" || { rm -rf "$tmp"; return 1; }
      (cd "$tmp/src" && go build -o "$tmp/pkg" .) || { err "Build failed."; rm -rf "$tmp"; return 1; }
      ;;
  esac
  if tar -tzf "$tmp/pkg" >/dev/null 2>&1; then
    mkdir -p "$tmp/x"; tar -xzf "$tmp/pkg" -C "$tmp/x"
    bin=$(find "$tmp/x" -type f -name backhaul | head -1)
    [[ -z $bin ]] && { err "No 'backhaul' binary inside the archive."; rm -rf "$tmp"; return 1; }
  else
    bin="$tmp/pkg"
  fi
  install -m 755 "$bin" "$BIN" && ok "Installed to ${BIN#$ROOT}"
  rm -rf "$tmp"
  return 0
}
ensure_binary() { [[ -x $BIN ]] || { warn "Backhaul binary not found."; install_binary; }; }

new_server_tunnel() {
  ensure_binary || return
  reset_vars
  echo; echo "${BD}== New tunnel: SERVER side (Iran) ==${N}"
  NAME=$(ask_name)
  TRANSPORT=$(ask_transport)
  [[ $TRANSPORT == udp ]] && HEARTBEAT=20
  local proto=tcp; [[ $TRANSPORT == udp ]] && proto=udp
  TUN_PORT=$(ask_tunnel_port "$(next_free_port 3080 "$proto")" "$proto")
  TOKEN=$(ask_token)
  mapfile -t PORTS < <(ask_ports)
  if [[ $TRANSPORT == tcp ]] && ask_yn "Also forward UDP through this TCP tunnel (accept_udp)?" n; then ACCEPT_UDP=true; fi
  if ask_yn "Change advanced settings?" n; then
    [[ $TRANSPORT != udp ]] && { ask_yn "nodelay (lower latency, less bandwidth)?" y || NODELAY=false; }
    KEEPALIVE=$(ask_int "keepalive_period (s)" "$KEEPALIVE" 1 3600)
    HEARTBEAT=$(ask_int "heartbeat (s)" "$HEARTBEAT" 1 3600)
    CHANNEL_SIZE=$(ask_int "channel_size" "$CHANNEL_SIZE" 1 1000000)
    is_mux && ask_mux_advanced
    if ask_yn "Enable the web monitoring interface?" n; then
      WEB_PORT=$(ask_int "web_port" "$(next_free_port 2060)" 1 65535)
    fi
    LOG_LEVEL=$(choose "log_level" 3 "panic|panic" "fatal|fatal" "error|error" "warn|warn" "info|info" "debug|debug" "trace|trace")
  fi
  is_tls && { make_cert "$NAME" || return; }
  write_server_conf
  ok "Config written: ${CONF_DIR#$ROOT}/$NAME.toml"
  server_firewall
  create_service "$NAME" "server $NAME ($TRANSPORT)"
  verify_start "$NAME"
  print_server_summary
}
print_server_summary() {
  local host
  host=$(ask "Public IP/domain of THIS server (goes into the client string)" "$(get_public_ip)")
  echo
  echo "${BD}=========== Tunnel '$NAME' (SERVER) ===========${N}"
  echo "  Transport   : $TRANSPORT"
  echo "  Tunnel port : $TUN_PORT"
  echo "  Token       : $TOKEN"
  echo "  Forwarding  : ${PORTS[*]}"
  echo
  echo "On the FOREIGN server run this script, choose 'New tunnel - CLIENT side'"
  echo "and paste this string:"
  echo
  echo "${G}$(make_conn_string "$host")${N}"
  echo "${BD}===============================================${N}"
}
new_client_tunnel() {
  ensure_binary || return
  reset_vars
  echo; echo "${BD}== New tunnel: CLIENT side (foreign) ==${N}"
  NAME=$(ask_name)
  local cs
  cs=$(ask "Paste the connection string from the server side (Enter = manual)" "")
  if [[ -n $cs ]]; then
    if parse_conn_string "$cs"; then ok "Parsed: $TRANSPORT -> $SRV_HOST:$SRV_PORT"
    else err "Invalid connection string."; return; fi
  else
    TRANSPORT=$(ask_transport)
    SRV_HOST=$(ask "Iran server IP or domain" "")
    [[ -z $SRV_HOST ]] && { err "Server address is required."; return; }
    SRV_PORT=$(ask_int "Tunnel port on the server" 3080 1 65535)
    TOKEN=$(ask_token)
  fi
  if ask_yn "Change advanced settings?" n; then
    POOL=$(ask_int "connection_pool" "$POOL" 1 1024)
    ask_yn "aggressive_pool?" n && AGGR=true
    RETRY=$(ask_int "retry_interval (s)" "$RETRY" 1 600)
    if [[ $TRANSPORT != udp ]]; then
      DIAL=$(ask_int "dial_timeout (s)" "$DIAL" 1 600)
      KEEPALIVE=$(ask_int "keepalive_period (s)" "$KEEPALIVE" 1 3600)
      ask_yn "nodelay?" y || NODELAY=false
    fi
    is_mux && ask_mux_advanced
    is_ws && EDGE_IP=$(ask "edge_ip (CDN edge IP, empty = none)" "")
    if ask_yn "Enable the web monitoring interface?" n; then
      WEB_PORT=$(ask_int "web_port" "$(next_free_port 2060)" 1 65535)
    fi
    LOG_LEVEL=$(choose "log_level" 5 "panic|panic" "fatal|fatal" "error|error" "warn|warn" "info|info" "debug|debug" "trace|trace")
  fi
  write_client_conf
  ok "Config written: ${CONF_DIR#$ROOT}/$NAME.toml"
  create_service "$NAME" "client $NAME ($TRANSPORT)"
  verify_start "$NAME"
}

load_server_globals() {
  local n="$1"
  reset_vars; NAME="$n"
  TRANSPORT=$(cfg_get "$n" transport)
  TUN_PORT=$(cfg_get "$n" bind_addr); TUN_PORT="${TUN_PORT##*:}"
  TOKEN=$(cfg_get "$n" token)
  ACCEPT_UDP=$(cfg_get "$n" accept_udp); ACCEPT_UDP="${ACCEPT_UDP:-false}"
  MUX_VER=$(cfg_get "$n" mux_version); MUX_VER="${MUX_VER:-1}"
  mapfile -t PORTS < <(get_ports "$n")
}
change_ports() {
  local n="$1" cur mode
  load_server_globals "$n"
  echo "Current forwarded ports: ${PORTS[*]:-(none)}"
  mode=$(choose "Action" 1 "replace|Replace all ports" "add|Add to existing ports")
  local newp=()
  mapfile -t newp < <(ask_ports)
  if [[ $mode == add ]]; then PORTS+=("${newp[@]}"); else PORTS=("${newp[@]}"); fi
  set_ports "$n" "${PORTS[@]}"
  ok "Ports updated: ${PORTS[*]}"
  server_firewall
  sd restart "${SVC_PREFIX}${n}"; verify_start "$n"
}
delete_tunnel() {
  local n="$1"
  ask_yn "Really delete tunnel '$n' (service + config)?" n || return
  sd stop "${SVC_PREFIX}${n}" 2>/dev/null
  sd disable "${SVC_PREFIX}${n}" >/dev/null 2>&1
  rm -f "$SVC_DIR/${SVC_PREFIX}${n}.service" "$CONF_DIR/$n.toml" "$CERT_DIR/$n.crt" "$CERT_DIR/$n.key"
  sd daemon-reload
  ok "Tunnel '$n' deleted."
}
follow_logs() {
  trap ':' INT
  journalctl -fu "${SVC_PREFIX}$1" 2>/dev/null
  trap - INT
}
manage_tunnel() {
  local n="$1" c role host
  while true; do
    [[ -e "$CONF_DIR/$n.toml" ]] || return
    role=$(cfg_role "$n")
    echo
    echo "${BD}Tunnel: $n${N} ($role, $(cfg_get "$n" transport))"
    echo "  1) Status              2) Last 60 log lines     3) Follow logs (Ctrl+C to stop)"
    echo "  4) Restart             5) Stop                  6) Start"
    [[ $role == server ]] && echo "  7) Change forwarded ports  8) Show client connection string"
    echo "  9) Show config        10) Edit config           11) Delete tunnel   0) Back"
    read -r -p "Select: " c
    case "$c" in
      1) systemctl status "${SVC_PREFIX}${n}" --no-pager 2>/dev/null | head -15 ;;
      2) journalctl -u "${SVC_PREFIX}${n}" -n 60 --no-pager 2>/dev/null ;;
      3) follow_logs "$n" ;;
      4) sd restart "${SVC_PREFIX}${n}"; verify_start "$n" ;;
      5) sd stop "${SVC_PREFIX}${n}"; ok "Stopped." ;;
      6) sd start "${SVC_PREFIX}${n}"; verify_start "$n" ;;
      7) [[ $role == server ]] && change_ports "$n" ;;
      8) if [[ $role == server ]]; then
           load_server_globals "$n"
           host=$(ask "Public IP/domain of THIS server" "$(get_public_ip)")
           echo; echo "${G}$(make_conn_string "$host")${N}"
         fi ;;
      9) echo "-----"; cat "$CONF_DIR/$n.toml"; echo "-----" ;;
      10) ${EDITOR:-$(command -v nano || echo vi)} "$CONF_DIR/$n.toml"
          ask_yn "Restart the tunnel to apply changes?" y && { sd restart "${SVC_PREFIX}${n}"; verify_start "$n"; } ;;
      11) delete_tunnel "$n"; [[ -e "$CONF_DIR/$n.toml" ]] || return ;;
      0) return ;;
      *) err "Invalid choice." ;;
    esac
  done
}
show_tunnels() {
  local n role tr addr st i=0
  echo; echo "${BD}Tunnels${N}"
  for n in $(list_tunnels); do
    i=$((i + 1))
    role=$(cfg_role "$n"); tr=$(cfg_get "$n" transport)
    if [[ $role == server ]]; then addr=$(cfg_get "$n" bind_addr); else addr=$(cfg_get "$n" remote_addr); fi
    if is_active "$n"; then st="${G}running${N}"; else st="${R}stopped${N}"; fi
    printf '  %2d) %-16s %-7s %-8s %-26s %b\n' "$i" "$n" "$role" "$tr" "$addr" "$st"
  done
  (( i == 0 )) && echo "  (none yet)"
}
pick_tunnel() {
  local TL=() c
  mapfile -t TL < <(list_tunnels)
  (( ${#TL[@]} == 0 )) && { warn "No tunnels yet."; return; }
  show_tunnels
  read -r -p "Tunnel number (0 = back): " c
  [[ $c =~ ^[0-9]+$ ]] && (( c >= 1 && c <= ${#TL[@]} )) && manage_tunnel "${TL[$((c - 1))]}"
}
restart_all() {
  local n
  for n in $(list_tunnels); do sd restart "${SVC_PREFIX}${n}"; info "restarted $n"; done
}
update_self() {
  ensure_deps curl || return 1
  local tmp
  tmp=$(mktemp)
  info "Downloading latest $CMD_NAME from $MY_REPO"
  curl -fL --retry 3 --connect-timeout 15 -o "$tmp" \
    "https://raw.githubusercontent.com/ParvaneZone/BH_Parv/main/backhaul-manager.sh" \
    || { err "Download failed."; rm -f "$tmp"; return 1; }
  install -m 755 "$tmp" "$SELF_CMD" && ok "Updated. Run '$CMD_NAME' to use the new version."
  rm -f "$tmp"
}
uninstall_all() {
  local n c
  warn "This removes ALL tunnels, configs, services and the backhaul binary."
  read -r -p "Type YES to continue: " c
  [[ $c == YES ]] || { info "Cancelled."; return; }
  for n in $(list_tunnels); do
    sd stop "${SVC_PREFIX}${n}" 2>/dev/null
    sd disable "${SVC_PREFIX}${n}" >/dev/null 2>&1
    rm -f "$SVC_DIR/${SVC_PREFIX}${n}.service"
  done
  rm -rf "$CONF_DIR" "$BIN"
  sd daemon-reload
  ok "Everything removed."
}
print_banner() {
  echo "${C}${BD}"
  echo "  ╔═══════════════════════════════════╗"
  echo "  ║             P A R V - B H          ║"
  echo "  ╚═══════════════════════════════════╝"
  echo "${N}"
  echo "  ${BD}${MY_NAME}${N}"
  echo "  Repo     : ${MY_REPO}"
  echo "  Telegram : ${MY_TELEGRAM}"
  echo "  Command  : ${G}${CMD_NAME}${N}  (run this anywhere to reopen the menu)"
}
main_menu() {
  local c
  while true; do
    print_banner
    show_tunnels
    echo
    echo "${BD}Backhaul Manager${N}"
    echo "  1) New tunnel - SERVER side (Iran)"
    echo "  2) New tunnel - CLIENT side (foreign)"
    echo "  3) Manage tunnels (status / logs / ports / delete)"
    echo "  4) Install / update Backhaul binary"
    echo "  5) Restart all tunnels"
    echo "  6) Uninstall everything"
    echo "  7) Update $CMD_NAME to the latest version"
    echo "  0) Exit"
    read -r -p "Select: " c || exit 0
    case "$c" in
      1) new_server_tunnel ;;
      2) new_client_tunnel ;;
      3) pick_tunnel ;;
      4) install_binary ;;
      5) restart_all ;;
      6) uninstall_all ;;
      7) update_self ;;
      0) exit 0 ;;
      *) err "Invalid choice." ;;
    esac
  done
}

if [[ -z $ROOT ]]; then
  (( EUID == 0 )) || { err "Run as root (sudo)."; exit 1; }
  command -v systemctl >/dev/null 2>&1 || { err "systemd is required."; exit 1; }
fi
mkdir -p "$CONF_DIR"
main_menu
