# managed/ — раздача замка через server-managed hooks (zero-touch)

Замок доставляется **не плагином**, а хуками прямо в managed-настройках админ-консоли
([claude.ai/admin-settings/claude-code](https://claude.ai/admin-settings/claude-code)).
Причина: плагинный маршрут требует материализацию в кэш (`plugins/cache/...`), которая
молча не отрабатывает в десктопе. Managed-хуки исполняются напрямую из `remote-settings.json`
— без шага кэша.

Логика замка целиком закодирована в команду хука — на машинах ноль файлов, ноль сети.
Читаемые исходники — `lock.ps1` (Windows) и `lock.sh` (macOS/Linux).

## ⚠️ Главное про эксплуатацию

**Managed-хуки не обновляются автоматически.** Плагины из маркетплейса подтягиваются сами
(`autoUpdate: true`), а хуки зашиты в настройки орга — их меняет только админ руками.
Значит **любая правка `lock.ps1` / `lock.sh` требует ручного шага**: перегенерировать JSON,
отдать админу, тот вставляет `hooks` в консоли, сотрудники перезапускают Claude Code.
Пока этого не сделано, у людей продолжает работать предыдущая версия логики.

## Владелец замка

`OWNER=USERNAME@COMPUTERNAME` (POSIX: `id -un` + `hostname`). Имя машины обязательно:
один человек часто работает с двух машин, и без хоста замок, поставленный с машины A,
выглядит «своим» на машине B и снимается без предупреждения. Детект Drive-конфликт-копий
это не спасает — он ловит только одновременный захват, а не последовательный.

## Файлы

**Исходники логики**
- **`lock.ps1`** — единый скрипт замка для Windows, диспатч по событию (`sessionstart|pretooluse|sessionend`).
  Точный порт `../plugins/collab/skills/setup-collab/assets/hooks/{check,guard,remove}-lock.ps1`.
- **`lock.sh`** — POSIX-порт того же поведения для macOS/Linux.

**Генераторы**
- **`gen-lock-crossplatform.ps1`** → `managed-settings.lock.crossplatform.json` — **боевой**.
  На каждое событие два хука: Windows (`powershell.exe -EncodedCommand <base64 UTF-16LE>`)
  и macOS/Linux (`echo <base64 UTF-8> | openssl base64 -d -A | sh`). Лишний для платформы
  просто не отрабатывает.
- **`gen-lock-dispatch.ps1`** → `managed-settings.lock.dispatch.json` — вариант с одной командой
  и OS-развилкой внутри. Оставлен как промежуточный, в проде не используется.
- **`gen-managed-hooks.ps1`** → `managed-settings.lock.json` + `managed-settings.smoke.json` —
  Windows-only версия и Фаза-0 смоук.

**Смоуки** — `managed-settings.smoke.json`, `managed-settings.lock.sessionstart-smoke.json`,
`managed-settings.single-sh-smoke.json`, `managed-settings.desktop-test.json`.

## Порядок раскатки (первичной)

1. **Фаза 0 (гейт):** добавить `hooks` из `managed-settings.smoke.json` к текущим managed-настройкам
   (не затирая `claudeMd` / `extraKnownMarketplaces` / `enabledPlugins`) → сохранить → полный рестарт
   у 2 машин → в папке проекта появляется `.mgmt_hook_ok.txt`. Нет — managed-хуки в десктопе
   не активируются, стоп.
2. **Фаза 1:** заменить smoke-`hooks` на `hooks` из `managed-settings.lock.crossplatform.json` →
   рестарт → проверить `WORKING_NOW.txt` и блокировку правок при чужом замке.

## Регенерация (после правки lock.ps1 / lock.sh)

```
powershell -NoProfile -ExecutionPolicy Bypass -File .\gen-lock-crossplatform.ps1
```

Затем отдать админу блок `hooks` из `managed-settings.lock.crossplatform.json` и дождаться,
пока он вставит его в консоль. Остальные генераторы прогонять только если правите
соответствующие им варианты.

**Проверка перед отдачей:** декодировать блобы обратно и убедиться, что в них попала правка —
Windows-блоб это base64 от UTF-16LE, macOS — от UTF-8. Шесть блобов: 3 события × 2 платформы.

## Заметки

- `-EncodedCommand` = base64 от UTF-16LE (Unicode) — генератор это делает.
- Файл крупный (~66 КБ: полный скрипт × 3 события × 2 платформы). Если консоль отвергнет
  по размеру — минифицировать исходники перед кодированием или перейти на гибрид
  (хук тянет скрипт).
- Чтение и поиск хуки не блокируют никогда — только `Edit` / `Write` / `NotebookEdit`.
- Пауза синхронизации Drive настраивается переменной `LOCK_SETTLE_SECONDS` (дефолт 10 с).
