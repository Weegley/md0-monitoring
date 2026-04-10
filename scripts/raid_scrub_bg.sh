#!/bin/bash

LOG_DIR="/var/log/raid"
mkdir -p "$LOG_DIR"

DAY=$(date '+%Y-%m-%d')
SCRUB_LOG="$LOG_DIR/scrub_$DAY.log"
LAUNCH_LOCK="/var/run/raid_scrub_bg.lock"

# Сериализуем сам момент запуска, чтобы два почти одновременных вызова
# не наспавнили лишние процессы. Дальше защиту держит flock внутри raid_scrub.sh.
exec 8>"$LAUNCH_LOCK"
if ! flock -n 8; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Background launcher is busy, skipping duplicate launch" >> "$SCRUB_LOG"
    exit 0
fi

nohup /usr/local/sbin/raid_scrub.sh >> "$SCRUB_LOG" 2>&1 </dev/null &
NEW_PID=$!
echo "$(date '+%Y-%m-%d %H:%M:%S') - RAID scrub launched in background (PID $NEW_PID)" >> "$SCRUB_LOG"
