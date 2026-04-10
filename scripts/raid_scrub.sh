#!/bin/bash

# --- Настройки ---
LOG_DIR="/var/log/raid"
mkdir -p "$LOG_DIR"

DATE=$(date '+%Y-%m-%d %H:%M:%S')
DAY=$(date '+%Y-%m-%d')
SCRUB_LOG="$LOG_DIR/scrub_$DAY.log"

SCRUB_FLAG="$LOG_DIR/.scrub_incomplete"
SCRUB_STAMP="$LOG_DIR/.last_scrub_ym"
LOCK_FILE="/var/run/raid_scrub.lock"
CURRENT_YM=$(date '+%Y-%m')

MD_NAME="md0"
MD_DEVICE="/dev/$MD_NAME"
MDSTAT="/proc/mdstat"
SYNC_ACTION="/sys/block/$MD_NAME/md/sync_action"

cleanup_on_signal() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - raid_scrub.sh interrupted, incomplete flag preserved" >> "$SCRUB_LOG"
    exit 1
}

trap cleanup_on_signal INT TERM HUP

exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    echo "$DATE - Another raid_scrub.sh instance is already running, exiting" >> "$SCRUB_LOG"
    exit 0
fi

# --- Проверка наличия RAID ---
if ! grep -q "^$MD_NAME\\b" "$MDSTAT"; then
    echo "$DATE - RAID $MD_NAME not active, keeping incomplete flag for retry" >> "$SCRUB_LOG"
    touch "$SCRUB_FLAG"
    exit 1
fi

# Если scrub уже идёт, просто выходим. Флаг не меняем:
# если это наш предыдущий запуск — он уже существует;
# если check запущен вручную извне — не создаём лишний retry-state.
if grep -q '\bcheck\b' "$MDSTAT"; then
    echo "$DATE - RAID scrub is already running, leaving state unchanged" >> "$SCRUB_LOG"
    exit 0
fi

echo "$DATE - Starting RAID scrub on $MD_DEVICE" >> "$SCRUB_LOG"
touch "$SCRUB_FLAG"

if echo check > "$SYNC_ACTION"; then
    echo "$DATE - RAID scrub issued successfully" >> "$SCRUB_LOG"
    echo "$DATE - Monitoring scrub progress until completion..." >> "$SCRUB_LOG"
else
    echo "$DATE - Failed to issue RAID scrub" >> "$SCRUB_LOG"
    exit 1
fi

# --- Отслеживание прогресса ---
# ВАЖНО: таймаут убран. Иначе можно потерять момент завершения scrub:
# ядро продолжит check, а скрипт уже не снимет флаг и не запишет stamp.
SLEEP_INTERVAL=60
SCRUB_OK=1

while grep -q '\bcheck\b' "$MDSTAT"; do
    if ! grep -q "^$MD_NAME\\b" "$MDSTAT"; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - RAID $MD_NAME inactive during scrub, aborting monitor" >> "$SCRUB_LOG"
        SCRUB_OK=0
        break
    fi

    DATE_NOW=$(date '+%Y-%m-%d %H:%M:%S')
    PROGRESS=$(grep -Eo '[0-9]+([.][0-9]+)?%' "$MDSTAT" | head -n1)
    [ -n "$PROGRESS" ] || PROGRESS="progress unavailable"
    echo "$DATE_NOW - Scrub in progress: $PROGRESS" >> "$SCRUB_LOG"

    sleep "$SLEEP_INTERVAL"
done

DATE_END=$(date '+%Y-%m-%d %H:%M:%S')
if [ "$SCRUB_OK" -eq 1 ] && ! grep -q '\bcheck\b' "$MDSTAT"; then
    echo "$DATE_END - RAID scrub completed successfully on $MD_DEVICE" >> "$SCRUB_LOG"
    rm -f "$SCRUB_FLAG"
    echo "$CURRENT_YM" > "$SCRUB_STAMP"
else
    echo "$DATE_END - RAID scrub incomplete, flag preserved for retry" >> "$SCRUB_LOG"
fi
