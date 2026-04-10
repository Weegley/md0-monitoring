#!/bin/bash
set -euo pipefail

LOG_DIR="/var/log/raid"

# Если каталога нет — выходим тихо
[ -d "$LOG_DIR" ] || exit 0

# Сжать обычные .log старше 7 дней
find "$LOG_DIR" -maxdepth 1 -type f -name '*.log' -mtime +7 -exec gzip -f {} \;

# Удалить сжатые логи старше 90 дней
find "$LOG_DIR" -maxdepth 1 -type f -name '*.log.gz' -mtime +90 -delete

