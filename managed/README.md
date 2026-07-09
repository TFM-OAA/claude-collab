# managed/ — раздача замка через server-managed hooks (zero-touch)

Замок доставляется **не плагином**, а хуками прямо в managed-настройках админ-консоли
([claude.ai/admin-settings/claude-code](https://claude.ai/admin-settings/claude-code)).
Причина: плагинный маршрут требует материализацию в кэш (`plugins/cache/...`), которая
молча не отрабатывает в десктопе. Managed-хуки исполняются напрямую из `remote-settings.json`
— без шага кэша.

Логика замка целиком закодирована в команду хука (`powershell.exe -EncodedCommand <base64>`) —
на машинах ноль файлов, ноль сети. Читаемый исходник — `lock.ps1`.

## Файлы
- **`lock.ps1`** — единый скрипт замка, диспатч по событию (`sessionstart|pretooluse|sessionend`).
  Точный порт `../plugins/collab/skills/setup-collab/assets/hooks/{check,guard,remove}-lock.ps1`.
- **`gen-managed-hooks.ps1`** — кодирует `lock.ps1` (событие пиннится на блоб) в base64 и собирает JSON.
- **`managed-settings.smoke.json`** — Фаза 0: тривиальный SessionStart-маркер (проверка, что канал фаирит).
- **`managed-settings.lock.json`** — Фаза 1: боевой замок (3 хука).

## Порядок раскатки
1. **Фаза 0 (гейт):** добавить `hooks` из `managed-settings.smoke.json` к текущим managed-настройкам
   (не затирая `extraKnownMarketplaces`/`enabledPlugins`) → сохранить → полный рестарт у 2 машин →
   в папке проекта появляется `.mgmt_hook_ok.txt`. Нет — managed-хуки в десктопе не активируются, стоп.
2. **Фаза 1:** заменить smoke-`hooks` на `hooks` из `managed-settings.lock.json` → рестарт → проверить
   `WORKING_NOW.txt` + блокировку правок при чужом замке.

## Регенерация (после правки lock.ps1)
```
powershell -NoProfile -ExecutionPolicy Bypass -File .\gen-managed-hooks.ps1
```

## Заметки
- `-EncodedCommand` = base64 от UTF-16LE (Unicode) — генератор это делает.
- Пока Windows-only (`powershell.exe`). Mac — отдельный sh-вариант + OS-дисптач, после подтверждения Mac-юзеров.
- `lock.json` крупный (~48 КБ: полный скрипт × 3 события). Если консоль отвергнет по размеру — минифицировать `lock.ps1` перед кодированием или перейти на гибрид (хук тянет скрипт).
