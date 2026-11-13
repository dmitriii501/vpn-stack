#!/bin/bash
# Проверяет доступность нод (443) и loadstat (8090) и пишет изменения в лог.
# Список нод: /etc/vpn-nodes (строки "NAME IP").
LOG=/var/log/vpn-health.log
STATE=/var/lib/vpn-health
NODES=/etc/vpn-nodes
mkdir -p "$STATE"
now=$(date -u "+%Y-%m-%d %H:%M:%S")

check() {
  local name=$1 ip=$2
  local vpn=down stat=down load="-"
  timeout 4 bash -c "echo >/dev/tcp/$ip/443" 2>/dev/null && vpn=up
  body=$(curl -fsS --max-time 4 "http://$ip:8090/" 2>/dev/null) && stat=up && load=$body
  local cur="$vpn/$stat/$load"
  local prev
  prev=$(cat "$STATE/$name" 2>/dev/null || echo "unknown")
  if [ "$cur" != "$prev" ]; then
    echo "$now $name $ip was=$prev now=$cur" >> "$LOG"
    echo "$cur" > "$STATE/$name"
  fi
}

[ -f "$NODES" ] || { echo "missing $NODES"; exit 1; }
while read -r name ip; do
  [ -z "${name:-}" ] && continue
  case "$name" in \#*) continue;; esac
  check "$name" "$ip"
done < "$NODES"
