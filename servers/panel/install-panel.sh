#!/usr/bin/env bash
# Идемпотентная установка панели (Ubuntu 24.04): Caddy, x-ui + Xray (Reality),
# vpn-web (nitro/srvx), PGlite, nftables (default-drop), fail2ban, бэкапы.
#
# Предполагается, что приложение уже собрано в /opt/vpn-web (functions/static/node_modules).
# Секреты — в /etc/vpn-web.env (см. vpn-web.env.example).
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
APP_DIR=/opt/vpn-web
BACKUP_REMOTE="${BACKUP_REMOTE:-root@31.59.169.171}"

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq caddy nftables fail2ban sqlite3 curl jq >/dev/null

# ---------- Caddy ----------
install -m 0644 "$HERE/Caddyfile" /etc/caddy/Caddyfile
systemctl enable caddy >/dev/null 2>&1 || true
systemctl reload caddy 2>/dev/null || systemctl restart caddy

# ---------- vpn-web ----------
install -d "$APP_DIR"
install -m 0644 "$HERE/vpn-web.service" /etc/systemd/system/vpn-web.service
install -m 0755 "$HERE/scripts/health.sh" "$APP_DIR/health.sh"
install -m 0644 "$HERE/vpn-health.service" /etc/systemd/system/vpn-health.service
install -m 0644 "$HERE/vpn-health.timer" /etc/systemd/system/vpn-health.timer
[ -f /etc/vpn-nodes ] || install -m 0644 "$HERE/vpn-nodes.example" /etc/vpn-nodes
[ -f /etc/vpn-web.env ] || { echo "ERROR: /etc/vpn-web.env missing (copy vpn-web.env.example)"; exit 1; }
systemctl daemon-reload
systemctl enable vpn-web >/dev/null 2>&1 || true
systemctl restart vpn-web
systemctl enable --now vpn-health.timer >/dev/null 2>&1 || true

# ---------- nftables ----------
install -d /etc/nftables.d
install -m 0644 "$HERE/panel.conf" /etc/nftables.d/panel.conf
cat > /etc/nftables.conf <<'CONF'
#!/usr/sbin/nft -f
# fail2ban manages its own table; include our static filter too
include "/etc/nftables.d/panel.conf"
CONF
nft -c -f /etc/nftables.conf
nft -f /etc/nftables.d/panel.conf
systemctl enable nftables >/dev/null 2>&1 || true

# ---------- fail2ban ----------
install -m 0644 "$HERE/fail2ban-sshd.local" /etc/fail2ban/jail.d/99-hardening.local
systemctl enable fail2ban >/dev/null 2>&1 || true
systemctl restart fail2ban

# ---------- backups ----------
install -m 0755 "$HERE/scripts/vpn-backup.sh" /usr/local/bin/vpn-backup.sh
sed "s|__BACKUP_REMOTE__|${BACKUP_REMOTE}|" "$HERE/vpn-backup.cron" > /etc/cron.d/vpn-backup
chmod 0644 /etc/cron.d/vpn-backup

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

echo "panel ready. Проверь: systemctl status vpn-web caddy fail2ban; curl -sI http://127.0.0.1:3000/"
