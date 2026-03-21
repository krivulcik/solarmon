#!/bin/sh
# Runs backup.sh on schedule: Sunday at 01:00
# Uses a simple sleep loop — no cron daemon needed.

echo "Backup scheduler started. Schedule: Sunday 01:00 UTC"

while true; do
    # Current day of week (0=Sunday) and hour
    DOW=$(date -u +%w)
    HOUR=$(date -u +%H)
    MIN=$(date -u +%M)

    if [ "$DOW" = "0" ] && [ "$HOUR" = "01" ] && [ "$MIN" = "00" ]; then
        echo "$(date -u '+%Y-%m-%d %H:%M:%S') Triggering scheduled backup..."
        /usr/local/bin/backup.sh
        # Sleep 61 minutes to avoid re-triggering in the same window
        sleep 3660
    else
        # Check every 30 seconds
        sleep 30
    fi
done
