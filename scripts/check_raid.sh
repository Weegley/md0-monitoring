#!/bin/bash

# --- Настройки ---
LOG_DIR="/var/log/raid"
mkdir -p "$LOG_DIR"

DATE=$(date '+%Y-%m-%d %H:%M:%S')
DAY=$(date '+%Y-%m-%d')
MD_DEVICE="/dev/md0"

# Логи
RAID_LOG="$LOG_DIR/md0_$DAY.log"
SMART_LOG="$LOG_DIR/smart_$DAY.log"
LAST_LOG="$LOG_DIR/.last_smart"
SCRUB_LOG="$LOG_DIR/scrub_$DAY.log"
MDADM_CACHE="$LOG_DIR/.last_mdadm_detail"

# Флаги/метки scrub
SCRUB_FLAG="$LOG_DIR/.scrub_incomplete"
SCRUB_STAMP="$LOG_DIR/.last_scrub_ym"
CURRENT_YM=$(date '+%Y-%m')
TODAY_DAY=$(date '+%-d')

# Создаём ежедневные лог-файлы заранее
touch "$RAID_LOG" "$SMART_LOG" "$SCRUB_LOG" "MDADM_CACHE"

get_disk_key() {
    local disk real id name

    real=$(readlink -f "$1")

    # Сначала предпочитаем самые стабильные идентификаторы WWN
    for id in /dev/disk/by-id/wwn-*; do
        [ -e "$id" ] || continue
        name=$(basename "$id")
        case "$name" in
            *-part[0-9]*) continue ;;
        esac
        [ "$(readlink -f "$id")" = "$real" ] || continue
        printf '%s\n' "$name"
        return 0
    done

    # Затем fallback на ATA ID
    for id in /dev/disk/by-id/ata-*; do
        [ -e "$id" ] || continue
        name=$(basename "$id")
        case "$name" in
            *-part[0-9]*) continue ;;
        esac
        [ "$(readlink -f "$id")" = "$real" ] || continue
        printf '%s\n' "$name"
        return 0
    done

    # Последний fallback — текущее имя устройства
    basename "$real"
}

get_disk_serial() {
    local smart_output serial

    smart_output=$1
    serial=$(awk -F: '/Serial Number:/ {sub(/^[[:space:]]+/, "", $2); print $2; exit}' <<< "$smart_output")
    [ -n "$serial" ] || serial="unknown"
    printf '%s\n' "$serial"
}

# --- Проверка состояния RAID ---
echo "$DATE - Starting RAID status check for $MD_DEVICE" >> "$RAID_LOG"

if command -v mdadm >/dev/null 2>&1 && [ -e "$MD_DEVICE" ]; then
  RAID_DETAIL=$(mdadm --detail "$MD_DEVICE" 2>&1)
  RAID_RC=$?

  {
    echo "Last update: $DATE"
    echo "Command: mdadm --detail $MD_DEVICE"
    echo "Exit code: $RAID_RC"
    echo
    echo "$RAID_DETAIL"
  } > "$MDADM_CACHE.tmp.$$"
  mv -f "$MDADM_CACHE.tmp.$$" "$MDADM_CACHE"

  if [ "$RAID_RC" -eq 0 ]; then
    RAID_STATUS=$(awk -F ' : ' '/State :/ {print $2; exit}' <<< "$RAID_DETAIL")
    [ -n "$RAID_STATUS" ] || RAID_STATUS="State unknown"
    echo "$DATE - State: $RAID_STATUS" >> "$RAID_LOG"
  else
    echo "$DATE - mdadm --detail failed for $MD_DEVICE (rc=$RAID_RC)" >> "$RAID_LOG"
    echo "$RAID_DETAIL" >> "$RAID_LOG"
  fi
else
  echo "$DATE - mdadm or $MD_DEVICE not available" >> "$RAID_LOG"

  {
    echo "Last update: $DATE"
    echo "Command: mdadm --detail $MD_DEVICE"
    echo "Exit code: 127"
    echo
    echo "mdadm or $MD_DEVICE not available"
  } > "$MDADM_CACHE.tmp.$$"
  mv -f "$MDADM_CACHE.tmp.$$" "$MDADM_CACHE"
fi


# --- Определяем реальные диски массива для SMART ---
RAID_DISKS=()
if command -v mdadm >/dev/null 2>&1 && [ -e "$MD_DEVICE" ]; then
    while IFS= read -r disk; do
        [ -b "$disk" ] || continue
        RAID_DISKS+=("$disk")
    done < <(
        mdadm --detail "$MD_DEVICE" 2>/dev/null \
        | awk '/(active sync|spare)/ {print $NF}' \
        | sort -u
    )
fi

# --- Проверка ключевых SMART атрибутов ---
SMART_IDS=(5 197 198)
declare -A SMART_KEYS=(
    ["5"]="Reallocated_Sector_Ct"
    ["197"]="Current_Pending_Sector"
    ["198"]="Offline_Uncorrectable"
)

echo "$DATE - Starting SMART check for $MD_DEVICE" >> "$SMART_LOG"

if ! command -v smartctl >/dev/null 2>&1; then
    echo "$DATE - smartctl not found, skipping SMART checks" >> "$SMART_LOG"
elif [ ${#RAID_DISKS[@]} -eq 0 ]; then
    echo "$DATE - Could not determine member disks for $MD_DEVICE, skipping SMART check" >> "$SMART_LOG"
else
    echo "$DATE - Member disks: ${RAID_DISKS[*]}" >> "$SMART_LOG"

    NEW_LAST_LOG="$LAST_LOG.tmp.$$"
    : > "$NEW_LAST_LOG"

    for disk in "${RAID_DISKS[@]}"; do
        DISK_KEY=$(get_disk_key "$disk")

        SMART_OUTPUT=$(smartctl -i -A "$disk" 2>&1)
        SMART_RC=$?

        if [ "$SMART_RC" -ne 0 ]; then
            echo "$DATE - smartctl failed for $disk [$DISK_KEY] (rc=$SMART_RC)" >> "$SMART_LOG"
            echo "$SMART_OUTPUT" >> "$SMART_LOG"
            continue
        fi

        DISK_SERIAL=$(get_disk_serial "$SMART_OUTPUT")

        echo "$DATE - SMART read OK for $disk [$DISK_KEY] serial=$DISK_SERIAL" >> "$SMART_LOG"

        for id in "${SMART_IDS[@]}"; do
            VALUE=$(awk -v id="$id" '$1==id {print $10; exit}' <<< "$SMART_OUTPUT")

            if [ -z "$VALUE" ]; then
                echo "$DATE - $disk [$DISK_KEY] serial=$DISK_SERIAL ${SMART_KEYS[$id]} not found in SMART output" >> "$SMART_LOG"
                continue
            fi

            PREV_VALUE=$(awk -F '\t' -v d="$DISK_KEY" -v i="$id" '$1==d && $4==i {print $5; exit}' "$LAST_LOG" 2>/dev/null)

            if [ "$VALUE" != "$PREV_VALUE" ]; then
                echo "$DATE - $disk [$DISK_KEY] serial=$DISK_SERIAL ${SMART_KEYS[$id]} changed: ${PREV_VALUE:-<none>} -> $VALUE" >> "$SMART_LOG"
            else
                echo "$DATE - $disk [$DISK_KEY] serial=$DISK_SERIAL ${SMART_KEYS[$id]} unchanged: $VALUE" >> "$SMART_LOG"
            fi

            printf '%s\t%s\t%s\t%s\t%s\n' "$DISK_KEY" "$disk" "$DISK_SERIAL" "$id" "$VALUE" >> "$NEW_LAST_LOG"
        done
    done

    mv -f "$NEW_LAST_LOG" "$LAST_LOG"
fi

# --- Авто-запуск scrub ---
echo "$DATE - Evaluating scrub schedule" >> "$SCRUB_LOG"

# Приоритет 1: если есть флаг недоделанного scrub — пробуем перезапустить/доследить.
if [ -f "$SCRUB_FLAG" ]; then
    echo "$DATE - Launching RAID scrub (incomplete run detected)" >> "$SCRUB_LOG"
    /usr/local/sbin/raid_scrub_bg.sh >> "$SCRUB_LOG" 2>&1

# Приоритет 2: 1-го числа запускаем scrub только один раз за месяц.
elif [ "$TODAY_DAY" -eq 1 ]; then
    LAST_YM=""
    [ -f "$SCRUB_STAMP" ] && LAST_YM=$(cat "$SCRUB_STAMP" 2>/dev/null)

    if [ "$LAST_YM" != "$CURRENT_YM" ]; then
        echo "$DATE - Launching RAID scrub (monthly schedule)" >> "$SCRUB_LOG"
        /usr/local/sbin/raid_scrub_bg.sh >> "$SCRUB_LOG" 2>&1
    else
        echo "$DATE - Monthly RAID scrub already completed for $CURRENT_YM, skipping" >> "$SCRUB_LOG"
    fi
else
    echo "$DATE - No scrub action required today" >> "$SCRUB_LOG"
fi
