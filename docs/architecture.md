# Архитектура

## Компоненты

### Панель (control plane) — `90.156.221.114`

| Компонент | Порт | Назначение |
|-----------|------|------------|
| Caddy | 80, 443 (bind 0.0.0.0), 8443 (bind 127.0.0.1) | сайт, TLS, reverse proxy на `:3000` |
| Xray (из x-ui) | 443 | VLESS+Reality, fallback на Caddy `:8443` |
| vpn-web (srvx/nitro) | 3000 (localhost) | сайт + API + подписки `/sub/<code>` |
| PGlite | — | встроенный Postgres (WASM), каталог `/opt/vpn-web/pgdata` |
| 3x-ui | 22825 (только localhost) | управление inbound'ом панели |
| x-ui subscriptions | 2096 (закрыт) | legacy-подписки x-ui, наружу не открыт |
| RustDesk (hbbs/hbbr) | 21115-21119 | удалённое управление |

Поток HTTPS-клиента на `:443`:
- обычный TLS с SNI `vpnsh.ru` / `defenceai.ru` → Reality-fallback → Caddy `127.0.0.1:8443` → сайт;
- VLESS+Reality клиент с правильным `pbk`/`sid`/`sni` → Xray.

Для РКН это выглядит как обычный HTTPS-сайт с валидным сертификатом Let's Encrypt.

### Ноды (data plane) — DE / PL / NL

| Компонент | Порт | Назначение |
|-----------|------|------------|
| Xray | 443 | VLESS+Reality (xhttp) |
| loadstat | 8090 (только с панели) | отдаёт % загрузки интерфейса |

Ноды не хранят состояние. Все параметры (UUID, publicKey, shortId, sni) лежат
в таблице `servers` PGlite на панели и попадают в подписку.

## Схема БД (PGlite, `public`)

| Таблица | Назначение |
|---------|------------|
| `servers` | ноды: host, port, country, uuid, public_key, short_id, sni, path, mode, active |
| `promo_codes` | промокоды (code, days, active, unlimited) |
| `subscriptions` | подписки (code, email, kind, expires, auto_renew, telegram_id, rebill_id) |
| `payments` | платежи Т-Банк (order_id, code, email, amount, status, payment_id) |
| `devices` | привязка устройств к коду (id, code, name, last_seen) — лимит устройств |
| `login_codes` | одноразовые коды входа по email |
| `tg_logins` | токены привязки Telegram |
| `_migrations` | применённые миграции |

## Роуты приложения (nitro/SSR)

- `/` — лендинг
- `/offer`, `/privacy` — юридические
- `/cabinet` — кабинет (вход по email-коду, Telegram)
- `/sub/$code` — **подписка**: отдаёт base64 `vless://` список, учитывает лимит устройств и срок
- `/pay/notify`, `/pay/renew` — вебхуки Т-Банк
- `/tg/hook` — вебхук Telegram-бота

## Домен и TLS

- `vpnsh.ru`, `www.vpnsh.ru` — основной сайт
- `defenceai.ru` — второй домен (fallback SNI)
- Сертификаты — Let's Encrypt (Caddy, автоматически)
- Reality `serverNames`: `www.microsoft.com` (ноды), `vpnsh.ru`/`defenceai.ru` (панель)

## Сеть и доступы

- SSH — только по ключу, root login только по ключу, fail2ban (sshd + 3x-ipl).
- nftables — default-drop; на панели снаружи открыты только необходимые порты.
- Межсервисный доступ (панель → нода `:8090`) ограничен по IP панели.
