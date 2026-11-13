# Runbook

Операционные процедуры. Все команды — от root на соответствующей машине.

## Проверить здоровье стека

```bash
# Панель
systemctl is-active caddy x-ui vpn-web fail2ban
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:3000/   # ожидаем 307
nft list table inet vpnfilter >/dev/null && echo nft-ok

# Ноды
systemctl is-active xray loadstat fail2ban
ss -tlnp | grep -E ':443|:8090'
```

Внешняя проверка портов — с любой ноды (у неё есть публичный egress):

```bash
P=90.156.221.114
for p in 22 80 443 2096 22825 3000 8090; do
  timeout 5 bash -c "echo >/dev/tcp/$P/$p" 2>/dev/null && echo "$p OPEN" || echo "$p closed"
done
```

## Перевыпуск подписки (смена UUID/shortId на ноде)

> ВНИМАНИЕ: смена UUID отключает всех клиентов, у которых старый конфиг.
> Делать только по необходимости (утечка), затем разослать новый `/sub/<code>`.

1. Сгенерировать новый UUID и shortId:
   ```bash
   uuidgen
   openssl rand -hex 4   # shortId, 8 hex
   ```
2. На ноде обновить `/usr/local/etc/xray/config.json` (`clients[].id`, `shortIds`),
   `xray run -test -config ...`, затем `systemctl restart xray`.
3. Обновить строку в БД панели (таблица `servers`, поля `uuid`, `short_id`) — через
   приложение/миграцию или скрипт `servers/panel/scripts/update-server.mjs`.
4. Проверить подписку: `curl https://vpnsh.ru/sub/<code>` — новый UUID в ссылках.

## Закрыть legacy-подписки x-ui (`:2096`)

Убедиться, что клиенты используют `/sub/<code>` (а не `:2096`), затем на панели
убрать `tcp dport 2096 accept` из `/etc/nftables.d/panel.conf` и применить:

```bash
nft -f /etc/nftables.d/panel.conf
```

## Восстановление из бэкапа

См. [`backup.md`](backup.md).

## Добавить новую ноду

1. Поднять Ubuntu 24.04, добавить SSH-ключ, закрыть пароль.
2. `servers/nodes/install-node.sh --country XX --reality-dest <host:443>`
3. Сгенерировать Reality-ключи: `xray x25519` (privateKey/publicKey), shortId.
4. Внести ноду в таблицу `servers` панели (`active=true`, `uuid`, `public_key`,
   `short_id`, `sni`, `path`, `mode`).
5. Открыть на панели доступ к `:8090` новой ноды (nftables set `panel_v4` уже покрывает
   панель; на ноде IP панели в `panel_v4`).
6. Проверить: `curl http://<node>:8090/` с панели, и `/sub/<code>` содержит новую ноду.

## Перезагрузка после сбоя

- nftables применяется из `/etc/nftables.conf` (include `vpnfilter.conf`), fail2ban
  поднимает свою таблицу сам.
- `vpn-web` поднимается systemd, `Restart=on-failure`.
- Проверить `vpn-health.timer` (пишет изменения доступности нод в `/var/log/vpn-health.log`).
