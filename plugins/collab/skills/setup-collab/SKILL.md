---
name: setup-collab
description: Включить совместную работу через Google Drive в любом проекте — развернуть автоматический LOCK-замок (WORKING_NOW.txt) на хуках Claude Code, команды /lock и /unlock, и правила COLLABORATION.md. Use this skill when the user wants to set up collaboration / "работу по очереди" / a project lock in ANOTHER project, "сделать проект совместным", "включить залочиваемость / WORKING_NOW / LOCK", protect a Google-Drive-synced folder from simultaneous edits, or replicate the lock/unlock mechanism elsewhere. Works on Windows (PowerShell). Installs into a target project folder.
---

# setup-collab — развернуть LOCK-обвязку совместной работы в проекте

Этот скилл ставит в **целевой проект** механику совместной работы по очереди: автоматический замок `WORKING_NOW.txt` на хуках Claude Code + команды `/lock`–`/unlock` + правила `COLLABORATION.md`. Рассчитано на папку, синхронизируемую через **Google Drive**, и на **Windows PowerShell**.

Скилл несёт в себе эталонные копии всех файлов (в `assets/`). Установка идемпотентна.

## Что устанавливается в целевой проект

- `.claude/hooks/{check,guard,set,remove}-lock.ps1` — портативные скрипты (сами находят папку проекта через `$env:CLAUDE_PROJECT_DIR` или «два уровня вверх»; пользователь — `$env:USERNAME`).
- `.claude/commands/lock.md` + `unlock.md` — команды `/lock` и `/unlock`.
- `.claude/settings.json` — три блока хуков: `SessionStart` (`startup|resume|clear`) → check-lock; `PreToolUse` (`Edit|Write|NotebookEdit`) → guard-lock; `SessionEnd` → remove-lock.
- `COLLABORATION.md` — правила (только если его ещё нет).
- Записи в `.gitignore` и раздел в `CLAUDE.md` (см. ниже).

## Порядок действий

### 1. Определить целевой проект
- По умолчанию целевой проект — **текущий** (`$CLAUDE_PROJECT_DIR` / рабочая папка сессии).
- Если пользователь назвал путь — взять его. Если непонятно, какой проект имелся в виду, — **спросить путь** у пользователя (AskUserQuestion).
- Не ставить обвязку в сам каталог скилла.

### 2. Скопировать файлы установщиком
Запустить (подставить реальный путь; `<SKILL_DIR>` — папка этого SKILL.md):
```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "<SKILL_DIR>\install-collab.ps1" -Target "<путь к целевому проекту>"
```
Скрипт копирует хуки и команды (через `Copy-Item`, сохраняя ASCII-without-BOM), кладёт `COLLABORATION.md` из шаблона **только если его нет**, и печатает в конце подсказку про `settings.json` (`[next] EXISTS` / `[next] MISSING`). Показать его вывод.

### 3. Вмержить хуки в `.claude/settings.json` целевого проекта
Сделать это **самостоятельно через Read/Edit** (а не скриптом — нужно аккуратно слить с существующим конфигом):
- Если установщик сказал `MISSING` → создать `<target>/.claude/settings.json`, скопировав содержимое `<SKILL_DIR>/assets/settings.hooks.json` как есть.
- Если `EXISTS` → прочитать существующий `settings.json` и **добавить** три записи хуков в объект `hooks` (эталон — `assets/settings.hooks.json`):
  - **не дублировать** уже присутствующие записи (проверить по `command`, содержащему `check-lock.ps1` / `guard-lock.ps1` / `remove-lock.ps1`);
  - **сохранить** все прочие хуки, `permissions` и любые другие поля;
  - сохранить валидный JSON.

### 4. `.gitignore` (если проект под git)
Если в корне целевого проекта есть `.gitignore` (или каталог `.git`), убедиться, что в нём присутствуют строки (добавить, если их нет):
```
WORKING_NOW*.txt
.claude/settings.local.json
```

### 5. Раздел в `CLAUDE.md` целевого проекта
- Если `CLAUDE.md` есть и в нём **нет** упоминания `COLLABORATION.md` — добавить короткий раздел:
  ```
  ## Совместная работа

  Папка на Google Drive, работа по очереди. **Обязательно прочитать [`COLLABORATION.md`](COLLABORATION.md)** — автоматический LOCK-замок (`WORKING_NOW.txt`) и правила во избежание конфликтов синхронизации.
  ```
- Если `CLAUDE.md` нет — создать минимальный с этим разделом.

### 6. Отчитаться пользователю (по-русски)
Кратко перечислить: что скопировано, как прошёл merge `settings.json`, тронуты ли `.gitignore`/`CLAUDE.md`. Дать памятку:
- Дальше каждый участник просто **открывает Claude Code** в этой папке — замок ставится сам на старте сессии; в конце — `/unlock` или просто закрыть сессию.
- **Второму участнику этот скилл не нужен** — обвязка уже лежит в проекте и синхронизируется через Drive. Скилл — только установщик; чтобы бутстрапить другие проекты, его папку можно скопировать в `~/.claude/skills/` на другой машине (`~/.claude` между аккаунтами не шарится).

## Проверка (по желанию / если просили)
В целевом проекте:
```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\.claude\hooks\check-lock.ps1"   # создаст WORKING_NOW.txt с OWNER=<USERNAME>, вернёт JSON
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\.claude\hooks\remove-lock.ps1"   # снимет ваш замок
```
Признак успеха: после check-lock в корне появляется `WORKING_NOW.txt` со строкой `OWNER=<ваш логин>`; remove-lock печатает `LOCK released`.

## Замечания
- Тюнинг паузы синхронизации: env-переменная `LOCK_SETTLE_SECONDS` (дефолт 10 с).
- Скрипты блокируют только Edit/Write/NotebookEdit при чужом замке; чтение/поиск всегда доступны.
- Конфликт-копии `WORKING_NOW (1).txt` скрипты **никогда не удаляют сами** — их сводят вручную (правило в COLLABORATION.md).
