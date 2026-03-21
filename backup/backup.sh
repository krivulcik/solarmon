#!/bin/sh
set -e

echo "$(date '+%Y-%m-%d %H:%M:%S') Starting backup..."

# Initialize repo if it doesn't exist yet
restic snapshots > /dev/null 2>&1 || {
    echo "Initializing restic repository..."
    restic init
}

# Backup InfluxDB data
restic backup /data/influxdb

# Prune old snapshots: keep 8 weekly, 24 monthly
restic forget --prune --keep-weekly 8 --keep-monthly 24

echo "$(date '+%Y-%m-%d %H:%M:%S') Backup complete."
