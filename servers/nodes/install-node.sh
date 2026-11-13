#!/usr/bin/env bash
# Идемпотентная установка VPN-ноды (Ubuntu 24.04): Xray (VLESS+Reality+xhttp),
# loadstat (:8090), nftables (default-drop), fail2ban, SSH hardening.
#
# Использование:
#   sudo ./install-node.sh --country DE --reality-dest www.microsoft.com:443 \
#        --panel-ip 90.156.221.114 [--uuid <uuid>] [--short-id <hex8>] [--sni <host>]
#
# Секреты (UUID, privateKey, shortId) можно передать аргументами или сгенерировать.
# Скрипт печатает publicKey (нужен для таблицы servers панели).
set -euo pipefail

COUNTRY=""
REALITY_DEST=""
PANEL_IP=""
UUID=""
SHORT_ID=""
SNI=""
XRAY_VERSION="26.11.9"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --country) COUNTRY="$2"; shift 2;;
    --reality-dest) REALITY_DEST="$2"; shift 2;;
    --panel-ip) PANEL_IP="$2"; shift 2;;
    --uuid) UUID="$2"; shift 2;;
    --short-id) SHORT_ID="$2"; shift 2;;
    --sni) SNI="$2"; shift 2;;
    *) echo "unknown arg: $1"; exit 1;;
  esac
done

[[ -n "$COUNTRY" && -n "$REALITY_DEST" && -n "$PANEL_IP" ]] || {
  echo "required: --country --reality-dest --panel-ip"; exit 1; }

UUID="${UUID:-$(cat /proc/sys/kernel/random/uuid)}"
SHORT_ID="${SHORT_ID:-$(openssl rand -hex 4)}"
SNI="${SNI:-${REALITY_DEST%%:*}}"

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq curl unzip jq nftables fail2ban python3 >/dev/null

# ---------- Xray ----------
if ! command -v xray >/dev/null 2>&1; then
  bash -c "$(curl -fsSL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install --version "$XRAY_VERSION"
fi
mkdir -p /usr/local/etc/xray

# Reality keypair
KEYPAIR=$(xray x25519)
PRIVATE_KEY=$(echo "$KEYPAIR" | awk -F': ' '/Private/{print $2}')
PUBLIC_KEY=$(echo "$KEYPAIR" | awk -F': ' '/Public|Password/{print $2}')

cat > /usr/local/etc/xray/config.json <<JSON
{
  "log": { "loglevel": "warning", "access": "/var/log/xray/access.log", "error": "/var/log/xray/error.log" },
  "inbounds": [{
    "listen": "0.0.0.0",
    "port": 443,
    "protocol": "vless",
    "settings": {
      "clients": [{ "id": "${UUID}", "email": "user1" }],
      "decryption": "none"
    },
    "streamSettings": {
      "network": "xhttp",
      "security": "reality",
      "realitySettings": {
        "show": false,
        "dest": "${REALITY_DEST}",
        "xver": 0,
        "serverNames": ["${SNI}"],
        "privateKey": "${PRIVATE_KEY}",
        "shortIds": ["${SHORT_ID}"]
      },
      "xhttpSettings": { "path": "/", "host": "", "mode": "auto" }
    }
  }],
  "outbounds": [{ "protocol": "freedom", "tag": "direct" }]
}
JSON
xray run -test -config /usr/local/etc/xray/config.json
systemctl enable xray >/dev/null 2>&1 || true
systemctl restart xray

# ---------- loadstat (:8090) ----------
install -m 0755 "$(dirname "$0")/loadstat.py" /usr/local/bin/loadstat.py
install -m 0644 "$(dirname "$0")/loadstat.service" /etc/systemd/system/loadstat.service
systemctl daemon-reload
systemctl enable loadstat >/dev/null 2>&1 || true
systemctl restart loadstat

# ---------- nftables ----------
install -d /etc/nftables.d
sed "s/__PANEL_IP__/${PANEL_IP}/" "$(dirname "$0")/vpnfilter.conf.tmpl" > /etc/nftables.d/vpnfilter.conf
cat > /etc/nftables.conf <<'CONF'
#!/usr/sbin/nft -f
include "/etc/nftables.d/vpnfilter.conf"
CONF
nft -c -f /etc/nftables.conf
nft -f /etc/nftables.d/vpnfilter.conf
systemctl enable nftables >/dev/null 2>&1 || true

# ---------- fail2ban ----------
install -m 0644 "$(dirname "$0")/fail2ban-sshd.local" /etc/fail2ban/jail.d/99-hardening.local
systemctl enable fail2ban >/dev/null 2>&1 || true
systemctl restart fail2ban

# ---------- SSH hardening ----------
install -d /etc/ssh/sshd_config.d
cat > /etc/ssh/sshd_config.d/99-hardening.conf <<'CONF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin prohibit-password
PermitEmptyPasswords no
MaxAuthTries 4
X11Forwarding no
CONF
sshd -t && systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true

echo "=============================================="
echo " node ready: $COUNTRY"
echo " uuid       = $UUID"
echo " shortId    = $SHORT_ID"
echo " sni        = $SNI"
echo " publicKey  = $PUBLIC_KEY   <-- внести в таблицу servers"
echo "=============================================="
