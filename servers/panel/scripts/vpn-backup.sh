#!/bin/bash
set -uo pipefail
TS=$(date +%Y%m%d-%H%M%S)
DEST=/var/backups/vpn
REMOTE=${BACKUP_REMOTE:-root@31.59.169.171}
REMOTE_DIR=/var/backups/vpn
KEEP_DAYS=14
mkdir -p "$DEST"
log(){ echo "[$(date +%H:%M:%S)] $*"; }

# 1) x-ui sqlite online backup (safe, no downtime)
sqlite3 /etc/x-ui/x-ui.db ".backup '$DEST/x-ui-$TS.db'" && log "x-ui db ok"

# 2) PGlite consistent snapshot: stop -> tar -> always start
log "stopping vpn-web for snapshot"
systemctl stop vpn-web || true
# wait up to 20s for full stop
for i in $(seq 1 20); do systemctl is-active --quiet vpn-web || break; sleep 1; done
if systemctl is-active --quiet vpn-web; then
  log "WARN: still active, force kill"
  systemctl kill -s SIGKILL vpn-web || true; sleep 2
fi
tar -C /opt/vpn-web -czf "$DEST/pgdata-$TS.tar.gz" pgdata && log "pgdata tar ok"
systemctl start vpn-web || true
for i in $(seq 1 30); do
  code=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:3000/ 2>/dev/null || true)
  [ "$code" = "307" ] && { log "vpn-web back up"; break; }
  sleep 1
done
[ "$(systemctl is-active vpn-web)" = "active" ] || { log "ERROR vpn-web not active!"; }

# 3) configs
tar -czf "$DEST/configs-$TS.tar.gz" \
  /etc/caddy/Caddyfile /etc/systemd/system/vpn-web.service /etc/nftables.d/panel.conf \
  /usr/local/etc/xray/config.json 2>/dev/null && log "configs ok"

# 4) manifest
( cd "$DEST"; sha256sum *-$TS.* > "manifest-$TS.txt" )

# 5) off-site
scp -q -i /root/.ssh/backup_ed25519 -o StrictHostKeyChecking=accept-new \
  "$DEST"/*-$TS.* "$DEST/manifest-$TS.txt" "$REMOTE:$REMOTE_DIR/" && log "shipped off-site"

# 6) rotation
find "$DEST" -type f -mtime +$KEEP_DAYS -delete
ssh -i /root/.ssh/backup_ed25519 -o StrictHostKeyChecking=accept-new "$REMOTE" \
  "find $REMOTE_DIR -type f -mtime +$KEEP_DAYS -delete" || true
log "backup done $TS"
