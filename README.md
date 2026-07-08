# claude-collab

Плагин Claude Code с одним скиллом — **`setup-collab`**: разворачивает в проекте автоматический замок совместной работы для папок, синхронизируемых через Google Drive.

## Зачем

Google Drive **не мержит** одновременные правки — при работе двух человек внахлёст он создаёт конфликт-копии (`файл (1).md`). Claude Code про синхронизацию не знает и может писать поверх чужих изменений. Замок заставляет работать по очереди.

## Что делает

`setup-collab` ставит в целевой проект:

- `.claude/hooks/*.ps1` — замок `WORKING_NOW.txt` на хуках Claude Code (SessionStart ставит замок, PreToolUse на Edit/Write блокирует при чужом замке, SessionEnd снимает);
- команды `/lock` и `/unlock`;
- `COLLABORATION.md` — правила работы по очереди.

Дальше каждый участник просто открывает Claude Code в этой папке — замок ставится сам на старте сессии, снимается при выходе. Обвязка синхронизируется вместе с папкой через Drive, второму участнику ставить ничего не нужно.

Чтение и поиск не блокируются — только запись (Edit/Write/NotebookEdit) при чужом активном замке.

Работает на Windows (PowerShell).

## Установка

### Как плагин (через маркетплейс)

```
/plugin marketplace add TFM-OAA/claude-collab
/plugin install collab@tfm-collab
```

Затем в целевом проекте вызвать скилл `/collab:setup-collab`, указав папку.

### Вручную (без маркетплейса)

Скопировать `plugins/collab/skills/setup-collab` в `~/.claude/skills/` и вызвать `setup-collab`, либо запустить установщик напрямую:

```
powershell -NoProfile -ExecutionPolicy Bypass -File install-collab.ps1 -Target "<путь к проекту>"
```

## Лицензия

[MIT](LICENSE).
