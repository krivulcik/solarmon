# Solarmon

Monitor solar production, battery state, and electricity consumption from a PI30-compatible inverter (Easun, Voltronic, etc.) with InfluxDB and Grafana dashboards.

## Quick Start

### Prerequisites

- Ubuntu 24.04 (or similar) with Docker and Docker Compose installed
- Inverter connected via USB (`/dev/hidraw0`)
- Python 3.10+

### 1. Clone and configure

```bash
git clone <repo-url> /opt/solarmon
cd /opt/solarmon
cp .env.example .env
```

Edit `.env` and fill in:

```
INFLUXDB_TOKEN=<generate a long random string>
INFLUXDB_ADMIN_PASSWORD=<pick a password>
AZURE_ACCOUNT_NAME=<your Azure storage account>
AZURE_ACCOUNT_KEY=<your Azure storage key>
RESTIC_PASSWORD=<pick a restic repo password>
```

### 2. Start the services

```bash
docker compose up -d
```

This starts InfluxDB (`:8086`), Grafana (`:3000`), and the backup scheduler.

### 3. Set up the data collector

```bash
sudo ./collector/setup.sh
```

This creates a Python virtualenv at `/opt/solarmon/venv`, installs mpp-solar with the InfluxDB output plugin, and installs a cron job that collects data every minute.

### 4. Open the dashboard

Go to `http://<your-ip>:3000` — the Solar Monitor dashboard is pre-configured and starts showing data within a minute. No login required (anonymous read access is enabled).

Admin login: `admin` / `admin` (change on first login via Grafana UI).

## Collector Setup Details

The collector runs on the host (not in Docker) because it needs direct USB access to the inverter.

`setup.sh` does the following:

1. Creates a virtualenv at `/opt/solarmon/venv`
2. Installs `mppsolar` and `influxdb-client`
3. Symlinks `collector/influx2.py` into the mppsolar outputs directory
4. Copies `.env.example` → `/opt/solarmon/.env` if no `.env` exists
5. Installs a cron job at `/etc/cron.d/solarmon`

The cron job runs two commands every minute:

- `QPIGS` — reads PV power, battery, load, grid, and temperature data
- `QMOD` — reads the current operating mode (Line / Battery / Fault)

All configuration (InfluxDB URL, token, org, bucket) is read from environment variables in `/opt/solarmon/.env`.

### Changing the inverter device path

If your inverter is not at `/dev/hidraw0`, edit `/etc/cron.d/solarmon` after running setup.

## Backup & Recovery

The `restic-backup` container backs up InfluxDB data to Azure Blob Storage weekly (Sunday 01:00 UTC). Retention: 8 weekly + 24 monthly snapshots.

### Manual backup

```bash
docker exec solarmon-backup /usr/local/bin/backup.sh
```

### Restore from backup

```bash
docker compose stop influxdb

# List snapshots
docker exec solarmon-backup restic snapshots

# Restore latest
docker exec solarmon-backup restic restore latest --target /

docker compose start influxdb
```

### Backup configuration

Set these in `.env`:

| Variable | Example |
|----------|---------|
| `RESTIC_REPOSITORY` | `azure:solarmon-backup:/` |
| `RESTIC_PASSWORD` | encryption password for the restic repo |
| `AZURE_ACCOUNT_NAME` | Azure storage account name |
| `AZURE_ACCOUNT_KEY` | Azure storage account key |

## Dashboard Panels

The provisioned Grafana dashboard includes:

- **PV Power** — current solar production (W)
- **Load** — current electricity consumption (W)
- **Battery** — state of charge gauge (%)
- **Battery Voltage** — current voltage (V)
- **Inverter Temperature** — heat sink temperature (°C)
- **Mode** — operating mode (Line / Battery / Standby / Fault)
- **Power Overview** — PV vs load vs apparent power over time
- **Battery Voltage** — voltage trend with SCC reading
- **Battery Current** — charge/discharge current over time
- **Battery Capacity** — SOC trend with color gradient
- **Inverter Temperature** — temperature trend
- **PV Input** — voltage and current (dual Y-axis)
- **AC Input / Output** — grid voltage, output voltage, load %
- **Daily PV Energy** — estimated daily energy production (Wh)

Dashboards are provisioned from `grafana/provisioning/` and can be edited in the Grafana UI.

## Architecture

See [ARCHITECTURE.md](ARCHITECTURE.md) for the full system design, data flow, file layout, and deployment details.

## Project Structure

```
solarmon/
├── docker-compose.yml       # InfluxDB, Grafana, backup scheduler
├── .env.example             # configuration template
├── collector/
│   ├── influx2.py           # InfluxDB 2.x output plugin for mpp-solar
│   ├── requirements.txt
│   └── setup.sh             # host setup: venv, deps, cron
├── backup/
│   ├── Dockerfile
│   ├── entrypoint.sh        # sleep-loop scheduler
│   └── backup.sh            # restic backup + prune
├── grafana/
│   └── provisioning/
│       ├── datasources/
│       │   └── influxdb.yml
│       └── dashboards/
│           ├── dashboards.yml
│           └── solar.json   # pre-built dashboard
└── data/                    # persistent volumes (gitignored)
    ├── influxdb/
    ├── grafana/
    └── restic-cache/
```
