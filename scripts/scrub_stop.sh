#!/bin/bash
# --- scrub_stop.sh: безопасная остановка RAID scrub ---

SCRUB_FLAG="/var/log/raid/.scrub_incomplete"
MD_SYSFS="/sys/block/md0/md"
BITMAP_BACKLOG="$MD_SYSFS/bitmap/backlog"
PROC_MDSTAT="/proc/mdstat"
SYNC_ACTION="$MD_SYSFS/sync_action"

FORCE_STOP=0

while getopts "f" opt; do
    case $opt in
        f) FORCE_STOP=1 ;;
    esac
done

show_progress() {
    if grep -q '^md0\b' "$PROC_MDSTAT"; then
        PROGRESS=$(grep -Eo '[0-9]+([.][0-9]+)?%' "$PROC_MDSTAT" | head -n1)
        [ -n "$PROGRESS" ] || PROGRESS="unknown"
        echo "Текущий прогресс scrub: $PROGRESS"
    else
        echo "RAID md0 не активен."
    fi
}

echo "Проверяем текущий прогресс scrub..."
show_progress

if ! grep -q '\bcheck\b' "$PROC_MDSTAT"; then
    echo "Scrub сейчас не выполняется."
    exit 0
fi

# --- Ждём завершения текущего chunk, если не force ---
if [ "$FORCE_STOP" -eq 0 ] && [ -r "$BITMAP_BACKLOG" ]; then
    while true; do
        BACKLOG=$(cat "$BITMAP_BACKLOG" 2>/dev/null)
        [ -n "$BACKLOG" ] || BACKLOG=0
        show_progress
        if [ "$BACKLOG" -eq 0 ]; then
            echo "Текущий chunk завершён, можно останавливать scrub."
            break
        else
            echo "Chunk ещё в работе (backlog=$BACKLOG), ждём 30 секунд..."
            sleep 30
        fi
    done
elif [ "$FORCE_STOP" -eq 1 ]; then
    echo "Force stop включён (-f), останавливаем scrub немедленно."
else
    echo "bitmap/backlog недоступен, выполняем обычную остановку."
fi

if echo idle > "$SYNC_ACTION"; then
    # scrub остановлен вручную, значит он не завершён — флаг должен остаться.
    touch "$SCRUB_FLAG"
    echo "Scrub остановлен. Флаг незавершённого scrub сохранён для последующего возобновления."
else
    echo "Не удалось остановить scrub."
    exit 1
fi
