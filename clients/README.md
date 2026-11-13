# Клиенты

## Как получить доступ

1. Получить **код подписки** (промокод) через кабинет/бота.
2. Ссылка подписки: `https://vpnsh.ru/sub/<CODE>` — её можно вставить в клиент
   как subscription URL, либо открыть в браузере и скопировать конфиг.

## Поддерживаемые клиенты

| Платформа | Клиент |
|-----------|--------|
| Android | v2rayNG, NekoBox |
| iOS | Streisand, FoXray |
| Windows | v2rayN, NekoRay |
| macOS | V2Box, Streisand |
| Linux | NekoRay, v2rayA |

Все клиенты должны поддерживать **VLESS + Reality + xhttp**.

## Формат подписки

`/sub/<code>` отдаёт `text/plain` с base64-списком `vless://` ссылок (по одной на ноду).
Заголовок `profile-update-interval: 1` — клиент обновляет раз в сутки.

Параметры ссылки:

```
vless://<UUID>@<host>:443?encryption=none&security=reality&pbk=<PUBLIC_KEY>&fp=chrome&sni=<SNI>&sid=<SHORT_ID>&spx=/&type=xhttp&path=/&mode=auto#<Страна>
```

## Ограничения

- Лимит устройств на код (таблица `devices`).
- Срок действия подписки (`subscriptions.expires`).

## Безопасность

- UUID общий на все ноды; при утечке — перевыпуск (см. `docs/runbook.md`).
- Не публиковать ссылку подписки.
