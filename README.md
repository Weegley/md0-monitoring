# RAID Tools for mdadm + Cockpit

A set of bash scripts and a simple Cockpit plugin for monitoring the `md0` array, reading logs, and running checks manually from a web UI.

---

## Overview

This project contains two parts:

1. **A script bundle for monitoring `md0`**
2. **A Cockpit plugin for viewing status, logs, and launching actions**

It is designed for a simple home or small NAS setup based on `mdadm`, with minimal moving parts and without requiring a full systemd-based workflow.

---

## 1. Script bundle for monitoring `md0`

Files:

- `check_raid.sh`
- `raid_scrub.sh`
- `raid_scrub_bg.sh`
- `scrub_stop.sh`

### `check_raid.sh`

Main daily check script.

What it does:
- checks the state of the `md0` array with `mdadm`
- discovers current member disks
- reads key SMART attributes from array disks
- writes daily logs
- launches scrub when needed
- tracks incomplete scrub state using a flag file

Logs:
- `md0_YYYY-MM-DD.log` — RAID array state
- `smart_YYYY-MM-DD.log` — SMART checks
- `scrub_YYYY-MM-DD.log` — scrub decisions and actions

State files:
- `.last_smart` — last saved SMART state
- `.scrub_incomplete` — incomplete scrub flag
- `.last_scrub_ym` — last successfully completed monthly scrub marker

### `raid_scrub.sh`

Starts `check` on `md0` and monitors progress until completion.

What it does:
- checks whether the array is active
- prevents parallel scrub execution
- logs scrub progress
- preserves the incomplete scrub flag if interrupted
- clears the flag and updates the monthly stamp after a successful finish

### `raid_scrub_bg.sh`

Background wrapper for `raid_scrub.sh`.

What it does:
- avoids nearly simultaneous duplicate launches
- starts `raid_scrub.sh` via `nohup`
- writes launch information into the log

### `scrub_stop.sh`

Graceful manual scrub stop helper.

What it does:
- shows current progress
- waits for the current chunk to finish when possible
- switches `sync_action` to `idle`
- preserves the incomplete scrub flag for later continuation

---

## 2. Cockpit plugin

The plugin adds a **RAID Tools** page to Cockpit.

It shows:
- `mdadm --detail /dev/md0`
- contents of `.last_smart`
- latest lines from the `md0` log
- latest lines from the `smart` log
- latest lines from the `scrub` log

It can launch:
- `check_raid.sh`
- `raid_scrub_bg.sh`
- `scrub_stop.sh`

Features:
- if today's log does not exist yet, the plugin falls back to the latest available log
- long log lines are shown without forced wrapping
- existing host scripts are called directly, without requiring a systemd service/unit migration

---

## Requirements

### For the scripts
- Linux
- `bash`
- `mdadm`
- `smartctl`
- an `md0` RAID array
- root privileges

### For the Cockpit plugin
- installed and working `cockpit`
- administrative access for running commands as root
- scripts available in `/usr/local/sbin/`

---

## Recommended script location

```bash
/usr/local/sbin/check_raid.sh
/usr/local/sbin/raid_scrub.sh
/usr/local/sbin/raid_scrub_bg.sh
/usr/local/sbin/scrub_stop.sh
```

Permissions:

```bash
chmod +x /usr/local/sbin/check_raid.sh
chmod +x /usr/local/sbin/raid_scrub.sh
chmod +x /usr/local/sbin/raid_scrub_bg.sh
chmod +x /usr/local/sbin/scrub_stop.sh
```

---

## Example cron setup

```cron
# check raid health
0 0 * * * root /usr/local/sbin/check_raid.sh
@reboot root sleep 60 && /usr/local/sbin/check_raid.sh
```

---

## Logs

By default, logs are written to:

```bash
/var/log/raid/
```

Typical files:
- `md0_YYYY-MM-DD.log`
- `smart_YYYY-MM-DD.log`
- `scrub_YYYY-MM-DD.log`

State files:
- `/var/log/raid/.last_smart`
- `/var/log/raid/.scrub_incomplete`
- `/var/log/raid/.last_scrub_ym`

---

## Cockpit plugin installation

If you already have the `raidtools/` plugin directory:

```bash
sudo rm -rf /usr/local/share/cockpit/raidtools
sudo mkdir -p /usr/local/share/cockpit/raidtools
sudo cp -r raidtools/* /usr/local/share/cockpit/raidtools/
```

Then reload the Cockpit page in your browser.

---

## Suggested repository structure

```text
.
├── README.md
├── LICENSE
├── scripts
│   ├── check_raid.sh
│   ├── raid_scrub.sh
│   ├── raid_scrub_bg.sh
│   └── scrub_stop.sh
└── cockpit
    └── raidtools
        ├── manifest.json
        ├── index.html
        ├── app.js
        ├── app.css
        └── README.md
```

---

## Project goals

The project is intentionally lightweight and practical.

Main goals:
- see RAID state every day
- keep a simple SMART history
- control monthly scrub behavior
- run or stop checks manually
- view everything from Cockpit without extra complexity

---

## Credits

Initial implementation and iterative refinement were created with ChatGPT assistance.

## License

MIT License. See `LICENSE`.

---

# RAID Tools for mdadm + Cockpit

Набор bash-скриптов и простой плагин для Cockpit для контроля массива `md0`, просмотра логов и ручного запуска проверок из веб-интерфейса.

---

## Обзор

Проект состоит из двух частей:

1. **Комплект скриптов для контроля `md0`**
2. **Плагин Cockpit для просмотра состояния, логов и запуска действий**

Проект задуман как лёгкий набор инструментов для домашнего или небольшого NAS на `mdadm`, без лишней обвязки и без обязательного перевода всего в systemd.

---

## 1. Комплект скриптов для контроля `md0`

Файлы:

- `check_raid.sh`
- `raid_scrub.sh`
- `raid_scrub_bg.sh`
- `scrub_stop.sh`

### `check_raid.sh`

Основной ежедневный скрипт проверки.

Что делает:
- проверяет состояние массива `md0` через `mdadm`
- определяет текущие диски массива
- читает ключевые SMART-атрибуты дисков
- пишет ежедневные логи
- при необходимости запускает scrub
- отслеживает незавершённый scrub через флаг

Логи:
- `md0_YYYY-MM-DD.log` — состояние массива
- `smart_YYYY-MM-DD.log` — SMART-проверка
- `scrub_YYYY-MM-DD.log` — решения и действия по scrub

Служебные файлы:
- `.last_smart` — последнее сохранённое состояние SMART
- `.scrub_incomplete` — флаг незавершённого scrub
- `.last_scrub_ym` — отметка последнего успешно завершённого ежемесячного scrub

### `raid_scrub.sh`

Запускает `check` для массива `md0` и отслеживает прогресс до завершения.

Что делает:
- проверяет, активен ли массив
- не допускает параллельный запуск второго scrub
- пишет прогресс в лог
- сохраняет флаг незавершённого scrub при прерывании
- снимает флаг и обновляет месячную отметку после успешного завершения

### `raid_scrub_bg.sh`

Обёртка для фонового запуска `raid_scrub.sh`.

Что делает:
- защищает от почти одновременного повторного старта
- запускает `raid_scrub.sh` через `nohup`
- пишет запуск в лог

### `scrub_stop.sh`

Аккуратная ручная остановка scrub.

Что делает:
- показывает текущий прогресс
- по возможности ждёт завершения текущего chunk
- переводит `sync_action` в `idle`
- сохраняет флаг незавершённого scrub для последующего продолжения

---

## 2. Плагин Cockpit

Плагин добавляет страницу **RAID Tools** в Cockpit.

Что показывает:
- `mdadm --detail /dev/md0`
- содержимое `.last_smart`
- последние строки `md0`-лога
- последние строки `smart`-лога
- последние строки `scrub`-лога

Что умеет запускать:
- `check_raid.sh`
- `raid_scrub_bg.sh`
- `scrub_stop.sh`

Особенности:
- если лог за текущий день ещё не создан, подхватывается последний доступный
- длинные строки в логах показываются без принудительного переноса
- существующие скрипты вызываются напрямую, без обязательного перехода на systemd unit/service

---

## Требования

### Для скриптов
- Linux
- `bash`
- `mdadm`
- `smartctl`
- RAID-массив `md0`
- права root

### Для плагина Cockpit
- установленный и работающий `cockpit`
- административный доступ для запуска команд от root
- наличие скриптов в `/usr/local/sbin/`

---

## Рекомендуемое размещение скриптов

```bash
/usr/local/sbin/check_raid.sh
/usr/local/sbin/raid_scrub.sh
/usr/local/sbin/raid_scrub_bg.sh
/usr/local/sbin/scrub_stop.sh
```

Права:

```bash
chmod +x /usr/local/sbin/check_raid.sh
chmod +x /usr/local/sbin/raid_scrub.sh
chmod +x /usr/local/sbin/raid_scrub_bg.sh
chmod +x /usr/local/sbin/scrub_stop.sh
```

---

## Пример cron

```cron
# check raid health
0 0 * * * root /usr/local/sbin/check_raid.sh
@reboot root sleep 60 && /usr/local/sbin/check_raid.sh
```

---

## Логи

По умолчанию логи пишутся в:

```bash
/var/log/raid/
```

Типовые файлы:
- `md0_YYYY-MM-DD.log`
- `smart_YYYY-MM-DD.log`
- `scrub_YYYY-MM-DD.log`

Служебные файлы:
- `/var/log/raid/.last_smart`
- `/var/log/raid/.scrub_incomplete`
- `/var/log/raid/.last_scrub_ym`

---

## Установка плагина Cockpit

Если у тебя уже есть директория `raidtools/`:

```bash
sudo rm -rf /usr/local/share/cockpit/raidtools
sudo mkdir -p /usr/local/share/cockpit/raidtools
sudo cp -r raidtools/* /usr/local/share/cockpit/raidtools/
```

После этого обнови страницу Cockpit в браузере.

---

## Рекомендуемая структура репозитория

```text
.
├── README.md
├── LICENSE
├── scripts
│   ├── check_raid.sh
│   ├── raid_scrub.sh
│   ├── raid_scrub_bg.sh
│   └── scrub_stop.sh
└── cockpit
    └── raidtools
        ├── manifest.json
        ├── index.html
        ├── app.js
        ├── app.css
        └── README.md
```

---

## Идея проекта

Проект намеренно сделан лёгким и практичным.

Главные цели:
- ежедневно видеть состояние массива
- иметь простую историю SMART
- контролировать ежемесячный scrub
- запускать и останавливать проверки вручную
- смотреть всё это из Cockpit без лишней сложности

---

## Credits

Initial implementation and iterative refinement were created with ChatGPT assistance.

## License

MIT License. См. файл `LICENSE`.
