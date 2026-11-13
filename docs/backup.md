# Бэкапы и восстановление

## Что бэкапится (панель)

| Данные | Как | Файл |
|--------|-----|------|
| БД сайта (PGlite) | остановка `vpn-web` → `tar pgdata` → старт | `pgdata-<TS>.tar.gz` |
| 3x-ui БД | `sqlite3 .backup` (онлайн) | `x-ui-<TS>.db` |
| Конфиги | Caddy, unit, nftables, xray | `configs-<TS>.tar.gz` |
| Манифест | sha256 всех файлов | `manifest-<TS>.txt` |

## Куда

- локально: `/var/backups/vpn/`
- off-site: нода DE `/var/backups/vpn/` (через `backup_ed25519`, root@DE)

## Расписание

`/etc/cron.d/vpn-backup` — ежедневно 03:30 UTC, лог в `/var/log/vpn-backup.log`.
Ротация — 14 дней (локально и на DE).

## Скрипт

`servers/panel/scripts/vpn-backup.sh` (устанавливается в `/usr/local/bin/vpn-backup.sh`).

Простой сайта на время снапшота PGlite — около 15 секунд. Для PGlite это
единственный консистентный способ (это один процесс, без TCP; `pg_dump` недоступен).

## Восстановление

### PGlite (БД сайта)

```bash
systemctl stop vpn-web
cd /opt/vpn-web
tar -xzf /var/backups/vpn/pgdata-<TS>.tar.gz     # заменит pgdata/
chown -R root:root pgdata
systemctl start vpn-web
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:3000/   # 307
```

### 3x-ui

```bash
systemctl stop x-ui
cp /var/backups/vpn/x-ui-<TS>.db /etc/x-ui/x-ui.db
systemctl start x-ui
```

### Конфиги

```bash
tar -xzf /var/backups/vpn/configs-<TS>.tar.gz -C /
systemctl daemon-reload
systemctl reload caddy 2>/dev/null; systemctl restart x-ui
nft -f /etc/nftables.d/panel.conf
```

## Проверка бэкапа

```bash
gzip -t /var/backups/vpn/*.tar.gz
sqlite3 /var/backups/vpn/x-ui-*.db 'pragma integrity_check;'   # ok
tar -tzf /var/backups/vpn/pgdata-*.tar.gz | grep -E 'PG_VERSION|global/pg_control'
```
