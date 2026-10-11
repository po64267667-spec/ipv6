#!/usr/bin/env bash
# hy2-ipv6-kit v1: native Hysteria 2, without a web panel.
set -Eeuo pipefail
umask 077
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

MODE=install
PUBLIC_IPV6=
BASE=/etc/hy2-ipv6-kit
BIN_DIR=/usr/local/lib/hy2-ipv6-kit
UNIT=hy2-ipv6-kit.service
UNIT_FILE=/etc/systemd/system/hy2-ipv6-kit.service
CRON_FILE=/etc/cron.d/hy2-ipv6-kit
MARKER=hy2-ipv6-kit-v1
HY_VERSION=2.13.0
ACME_VERSION=3.1.6
ACME_SHA=c7d68b021cfd6380ea83a82962abde5b484779fee0b97d38681dfa1396bbc8d7
TEMP_DIR=

die() { printf '错误：%s\n' "$*" >&2; exit 1; }
say() { printf '%s\n' "$*"; }
cleanup() {
  if [[ $TEMP_DIR == /tmp/hy2-ipv6-kit.* && -d $TEMP_DIR ]]; then
    rm -rf -- "$TEMP_DIR"
  fi
}
trap cleanup EXIT
trap 'printf "执行失败（第 %s 行）。修正错误后可重跑；已有凭据不会重新生成。\n" "$LINENO" >&2' ERR

usage() {
  cat <<'EOF'
用法：bash deploy-hy2-ipv6.sh [install|check|show] [--ipv6 公网IPv6]
默认 install：只询问公网 IPv6，其余自动配置。
--check / check：只读检查，不显示密码或二维码。
show：主动显示连接链接和终端二维码。
EOF
}
while (($#)); do
  case $1 in
    install|check|show) MODE=$1 ;;
    --check) MODE=check ;;
    --ipv6) (($# >= 2)) || die '--ipv6 后需要地址'; PUBLIC_IPV6=$2; shift ;;
    -h|--help|help) usage; exit 0 ;;
    *) die "未知参数：$1" ;;
  esac
  shift
done
[[ $EUID == 0 ]] || die '请用 root 运行，例如 sudo bash deploy-hy2-ipv6.sh'
[[ -r /etc/os-release && -d /run/systemd/system ]] || die '需要运行 systemd 的 Debian / Ubuntu 主机'
# This file belongs to the OS; no downloaded code is sourced.
# shellcheck source=/dev/null
. /etc/os-release
case "$ID:$VERSION_ID" in
  debian:12|debian:13|ubuntu:22.04|ubuntu:24.04) ;;
  *) die '仅支持 Debian 12/13 或 Ubuntu 22.04/24.04' ;;
esac

managed_paths() {
  local directory file fragment
  for directory in "$BASE" "$BIN_DIR"; do
    [[ ! -L $directory ]] || die "拒绝使用符号链接目录：$directory"
    if [[ -e $directory ]]; then
      [[ -d $directory && -f $directory/.managed-by ]] || die "已有未管理目录：$directory；不会覆盖"
      [[ $(cat "$directory/.managed-by") == "$MARKER" ]] || die "已有其他程序目录：$directory；不会覆盖"
    fi
  done
  for file in "$UNIT_FILE" "$CRON_FILE" "$BASE/server.yaml"; do
    [[ ! -L $file ]] || die "拒绝使用符号链接文件：$file"
    if [[ -e $file ]]; then
      if [[ ! -f $file ]] || ! grep -Fxq "# managed-by: $MARKER" "$file"; then
        die "已有未管理文件：$file；不会覆盖"
      fi
    fi
  done
  fragment=$(systemctl show "$UNIT" --property=FragmentPath --value 2>/dev/null || true)
  [[ -z $fragment || $fragment == "$UNIT_FILE" ]] || die "已有其他服务：$fragment；不会覆盖"
}

port_check() {
  local tcp_busy udp_busy main_pid owners pid
  [[ -r /proc/net/tcp6 && -r /proc/net/udp6 ]] || die '内核未提供 IPv6 TCP/UDP，请先启用 IPv6'
  tcp_busy=$(awk 'FNR>1 && $2 ~ /:0050$/ && $4=="0A" {print $2}' /proc/net/tcp /proc/net/tcp6)
  [[ -z $tcp_busy ]] || die 'TCP 80 已被占用；ACME 需要此端口。不会停止已有服务，请先规划或使用新主机。'
  udp_busy=$(awk 'FNR>1 && $2 ~ /:01BB$/ {print $2}' /proc/net/udp /proc/net/udp6)
  if [[ -n $udp_busy ]]; then
    main_pid=$(systemctl show "$UNIT" --property=MainPID --value 2>/dev/null || true)
    [[ -f $BASE/.managed-by && ${main_pid:-0} != 0 ]] || die 'UDP 443 已被占用（可能是现有 3X-UI）。不会停止已有服务，请使用新主机或先规划端口。'
    command -v ss >/dev/null || die '无法确认 UDP 443 的进程归属；不会继续安装'
    owners=$(ss -H -lunp 'sport = :443' | grep -o 'pid=[0-9]*' | cut -d= -f2 || true)
    [[ -n $owners ]] || die '无法确认 UDP 443 的进程归属；不会继续安装'
    while IFS= read -r pid; do
      [[ $pid == "$main_pid" ]] || die 'UDP 443 还被其他进程占用；不会停止已有服务'
    done <<< "$owners"
  fi
}

load_credentials() {
  [[ -f $BASE/credentials.env && ! -L $BASE/credentials.env ]] || die '尚无连接信息，请先安装'
  SAVED_IPV6=$(sed -n 's/^PUBLIC_IPV6=//p' "$BASE/credentials.env")
  AUTH_PASSWORD=$(sed -n 's/^AUTH_PASSWORD=//p' "$BASE/credentials.env")
  OBFS_PASSWORD=$(sed -n 's/^OBFS_PASSWORD=//p' "$BASE/credentials.env")
  [[ $SAVED_IPV6 =~ ^[0-9a-f:]+$ && $AUTH_PASSWORD =~ ^[0-9a-f]{48}$ && $OBFS_PASSWORD =~ ^[0-9a-f]{48}$ ]] || die '保存的凭据格式不正确；未修改它们'
}

show_connection() {
  load_credentials
  local uri
  uri="hysteria2://${AUTH_PASSWORD}@[${SAVED_IPV6}]:443/?sni=${SAVED_IPV6//:/%3A}&obfs=salamander&obfs-password=${OBFS_PASSWORD}#HY2-IPv6"
  say '以下链接和二维码包含连接密码：'
  printf '\n%s\n\n' "$uri"
  if command -v qrencode >/dev/null; then
    printf '%s' "$uri" | qrencode -t ANSIUTF8
  fi
  say "二维码 PNG：$BASE/connection.png"
}

check_status() {
  local service_state enabled_state service_pid incomplete=0
  managed_paths
  port_check
  say '本机检查：TCP 80 空闲；UDP 443 空闲或归属本包服务。'
  if [[ -f $BASE/.managed-by ]]; then
    service_state=$(systemctl is-active "$UNIT" 2>/dev/null || true)
    say "服务状态：$service_state"
    [[ $service_state == active ]] || incomplete=1
    enabled_state=$(systemctl is-enabled "$UNIT" 2>/dev/null || true)
    say "开机启动：$enabled_state"
    [[ $enabled_state == enabled ]] || incomplete=1
    if [[ $service_state == active ]]; then
      service_pid=$(systemctl show "$UNIT" --property=MainPID --value)
      if ! ss -H -lunp 'sport = :443' | grep -q "pid=$service_pid,"; then
        say '本包服务没有监听 UDP 443。'
        incomplete=1
      fi
    fi
    if [[ -s $BASE/tls/fullchain.pem ]] && command -v openssl >/dev/null; then
      openssl x509 -in "$BASE/tls/fullchain.pem" -noout -dates -ext subjectAltName
      openssl x509 -in "$BASE/tls/fullchain.pem" -noout -checkend 86400 >/dev/null || die '证书将在 24 小时内到期或已经过期，请检查续期日志'
    else
      say '证书尚未安装；可以重跑 install 继续。'
      incomplete=1
    fi
    if [[ -f $CRON_FILE ]]; then
      say '自动续期任务：已配置（每 6 小时检查，约 3 天续期）'
      [[ $(systemctl is-active cron 2>/dev/null || true) == active ]] || incomplete=1
    else
      say '自动续期任务：尚未配置。'
      incomplete=1
    fi
  else
    say '尚未安装；本机端口预检通过。'
  fi
  say '公网 IPv6 的 TCP 80 / UDP 443 是否可达仍需外网验证；本机监听不代表网络可达。'
  [[ $incomplete == 0 ]] || die '安装尚未完成或服务/cron 未运行；修复后重跑 install'
}

managed_paths
if [[ $MODE == check ]]; then check_status; exit 0; fi
if [[ $MODE == show ]]; then show_connection; exit 0; fi
port_check
case $(uname -m) in
  x86_64) HY_ARCH=amd64; HY_SHA=907ba8c9693edb104b20582681fb7dc15639d5b64a9cbb616a7b539190a86691 ;;
  aarch64|arm64) HY_ARCH=arm64; HY_SHA=a68a61a84452ca250ce0368202521965ca9cc9d801a404f1dc9008ac6cf677a7 ;;
  *) die '仅支持 amd64 / arm64 主机' ;;
esac
if [[ -f $BASE/credentials.env ]]; then
  load_credentials
  [[ -n $PUBLIC_IPV6 ]] || PUBLIC_IPV6=$SAVED_IPV6
elif [[ -z $PUBLIC_IPV6 ]]; then
  read -r -p '请输入商家分配的公网 IPv6（不是 guest 内网 fd42 地址）：' PUBLIC_IPV6
fi
[[ $PUBLIC_IPV6 == \[*\] ]] && PUBLIC_IPV6=${PUBLIC_IPV6:1:${#PUBLIC_IPV6}-2}
[[ $PUBLIC_IPV6 =~ ^[0-9a-fA-F:]+$ && $PUBLIC_IPV6 == *:* ]] || die '请输入 IPv6 地址，不包含端口、域名或前缀长度'

say '安装必要依赖（不修改 SSH，不清空防火墙）……'
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ca-certificates curl openssl socat cron python3 qrencode iproute2
PUBLIC_IPV6=$(python3 - "$PUBLIC_IPV6" <<'PY'
import ipaddress, sys
try:
    address = ipaddress.IPv6Address(sys.argv[1])
    if not address.is_global or address.is_multicast or address.ipv4_mapped:
        raise ValueError()
    print(address.compressed)
except ValueError:
    sys.exit('需要真实公网 IPv6；ULA、链路本地、文档示例和组播地址不可用于签发。')
PY
)
if [[ -f $BASE/credentials.env ]]; then
  [[ $PUBLIC_IPV6 == "$SAVED_IPV6" ]] || die '输入 IPv6 与已保存地址不同；不会改写现有配置'
fi
port_check
for directory in "$BASE" "$BIN_DIR"; do
  if [[ ! -d $directory ]]; then
    install -d -m 0700 "$directory"
    printf '%s\n' "$MARKER" > "$directory/.managed-by"
  fi
done
install -d -m 0700 "$BASE/tls" "$BASE/acme"
if [[ ! -f $BASE/credentials.env ]]; then
  AUTH_PASSWORD=$(openssl rand -hex 24)
  OBFS_PASSWORD=$(openssl rand -hex 24)
  printf 'PUBLIC_IPV6=%s\nAUTH_PASSWORD=%s\nOBFS_PASSWORD=%s\n' "$PUBLIC_IPV6" "$AUTH_PASSWORD" "$OBFS_PASSWORD" > "$BASE/credentials.env.new"
  chmod 0600 "$BASE/credentials.env.new"
  mv -T "$BASE/credentials.env.new" "$BASE/credentials.env"
fi
load_credentials
if [[ ! -f $BASE/server.yaml ]]; then
  cat > "$BASE/server.yaml" <<EOF
# managed-by: $MARKER
listen: "[::]:443"
tls:
  cert: "$BASE/tls/fullchain.pem"
  key: "$BASE/tls/private.key"
auth:
  type: password
  password: "$AUTH_PASSWORD"
obfs:
  type: salamander
  salamander:
    password: "$OBFS_PASSWORD"
EOF
  chmod 0600 "$BASE/server.yaml"
fi
TEMP_DIR=$(mktemp -d /tmp/hy2-ipv6-kit.XXXXXX)
download_verified() {
  local url=$1 digest=$2 destination=$3
  curl --fail --location --silent --show-error --retry 3 --connect-timeout 15 --max-time 240 --proto '=https' --proto-redir '=https' "$url" -o "$TEMP_DIR/download"
  printf '%s  %s\n' "$digest" "$TEMP_DIR/download" | sha256sum --check --status || die '官方下载文件 SHA-256 校验失败；未执行该文件'
  install -m 0700 "$TEMP_DIR/download" "$destination.new"
  mv -T "$destination.new" "$destination"
}
if [[ ! -f $BIN_DIR/hysteria ]] || ! printf '%s  %s\n' "$HY_SHA" "$BIN_DIR/hysteria" | sha256sum --check --status; then
  say "下载并校验官方 Hysteria $HY_VERSION ($HY_ARCH)……"
  download_verified "https://github.com/HyNetworks/hysteria/releases/download/app/v${HY_VERSION}/hysteria-linux-${HY_ARCH}" "$HY_SHA" "$BIN_DIR/hysteria"
fi
if [[ ! -f $BASE/acme/acme.sh ]] || ! printf '%s  %s\n' "$ACME_SHA" "$BASE/acme/acme.sh" | sha256sum --check --status; then
  say "下载并校验官方 acme.sh $ACME_VERSION……"
  download_verified "https://raw.githubusercontent.com/acmesh-official/acme.sh/${ACME_VERSION}/acme.sh" "$ACME_SHA" "$BASE/acme/acme.sh"
  bash -n "$BASE/acme/acme.sh"
fi

# Keep the CA and renewal state isolated; leave any existing ~/.acme.sh alone.
ACME="$BASE/acme/acme.sh"
"$ACME" --home "$BASE/acme" --set-default-ca --server letsencrypt
"$ACME" --home "$BASE/acme" --register-account --server letsencrypt
if command -v ufw >/dev/null && LC_ALL=C ufw status | grep -q '^Status: active'; then
  say 'UFW 已启用：仅添加 TCP 80 / UDP 443 放行规则。'
  ufw allow 80/tcp >/dev/null
  ufw allow 443/udp >/dev/null
fi
say "申请或检查公网 IPv6 的 Let's Encrypt 正式证书……"
issue_rc=0
"$ACME" --home "$BASE/acme" --issue --server letsencrypt --standalone --listen-v6 \
  -d "$PUBLIC_IPV6" --certificate-profile shortlived --days 3 --keylength ec-256 || issue_rc=$?
[[ $issue_rc == 0 || $issue_rc == 2 ]] || die '签发未成功。确认商家及主机防火墙放行公网 IPv6 TCP 80，重跑即可继续；不会改成自签或跳过验证。'
if [[ ! -f $UNIT_FILE ]]; then
  cat > "$UNIT_FILE" <<EOF
# managed-by: $MARKER
[Unit]
Description=Native Hysteria 2 IPv6 (hy2-ipv6-kit)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=$BIN_DIR/hysteria server --config $BASE/server.yaml
Restart=on-failure
RestartSec=3
TimeoutStopSec=10
NoNewPrivileges=true
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF
  chmod 0644 "$UNIT_FILE"
fi
systemctl daemon-reload
"$ACME" --home "$BASE/acme" --install-cert -d "$PUBLIC_IPV6" --ecc \
  --key-file "$BASE/tls/private.key" --fullchain-file "$BASE/tls/fullchain.pem" \
  --reloadcmd "systemctl restart $UNIT"
chmod 0600 "$BASE/tls/private.key" "$BASE/tls/fullchain.pem" "$BASE/credentials.env" "$BASE/server.yaml"
openssl x509 -in "$BASE/tls/fullchain.pem" -noout -checkend 86400 >/dev/null || die '安装证书无效或不足 24 小时有效期'
openssl x509 -in "$BASE/tls/fullchain.pem" -noout -checkip "$PUBLIC_IPV6" >/dev/null || die '证书 IP SAN 与保存的公网 IPv6 不匹配'
if [[ ! -f $CRON_FILE ]]; then
  cat > "$CRON_FILE" <<EOF
# managed-by: $MARKER
SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
0 */6 * * * root umask 077; $ACME --cron --home $BASE/acme --server letsencrypt >> $BASE/acme/renew.log 2>&1
EOF
  chmod 0644 "$CRON_FILE"
fi
systemctl enable --now cron
systemctl enable --now "$UNIT"
sleep 1
systemctl is-active --quiet "$UNIT" || die "服务未启动。请检查 journalctl -u $UNIT；重跑会保留凭据。"
MAIN_PID=$(systemctl show "$UNIT" --property=MainPID --value)
ss -H -lunp 'sport = :443' | grep -q "pid=$MAIN_PID," || die '服务尚未监听 UDP 443，请检查服务日志'

URI="hysteria2://${AUTH_PASSWORD}@[${SAVED_IPV6}]:443/?sni=${SAVED_IPV6//:/%3A}&obfs=salamander&obfs-password=${OBFS_PASSWORD}#HY2-IPv6"
printf '%s\n' "$URI" > "$BASE/connection.txt"
printf '%s' "$URI" | qrencode -o "$BASE/connection.png"
chmod 0600 "$BASE/connection.txt" "$BASE/connection.png"
say '安装完成：原生 Hysteria 2 已启动，证书续期后会自动重启服务读取新证书。'
show_connection
say '请在有 IPv6 的客户端网络实测网页；本机启动成功不代表公网 UDP 可达。'
