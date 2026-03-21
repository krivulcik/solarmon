# Solarmon — Architecture & Plan

Solar production and electricity consumption monitoring system for a standalone Ubuntu 24.04 machine.

## Overview

```
┌─────────────────────────────────────────────────────────────────┐
│  Ubuntu 24.04 Host                                              │
│                                                                 │
│  ┌──────────────────────┐        ┌────────────────────────────┐ │
│  │ Host (cron, 1 min)   │        │ Docker Compose             │ │
│  │                      │        │                            │ │
│  │  mpp-solar (venv)    │ HTTP   │  ┌──────────────────────┐  │ │
│  │  PI30 protocol   ────────────►│  │ InfluxDB 2.x        │  │ │
│  │  /dev/hidraw0        │ :8086  │  │ bucket: solar        │  │ │
│  │                      │        │  │ org: home            │  │ │
│  └──────────────────────┘        │  └──────────┬───────────┘  │ │
│                                  │             │              │ │
│                                  │  ┌──────────▼───────────┐  │ │
│                                  │  │ Grafana              │  │ │
│                                  │  │ :3000                │  │ │
│                                  │  │ auto-provisioned     │  │ │
│                                  │  └──────────────────────┘  │ │
│                                  │                            │ │
│                                  │  ┌──────────────────────┐  │ │
│                                  │  │ restic-backup        │  │ │
│                                  │  │ daily cron           │  │ │
│                                  │  │ → Azure Blob Storage │  │ │
│                                  │  └──────────────────────┘  │ │
│                                  └────────────────────────────┘ │
│                                                                 │
│  Persistent data: ./data/ (host-mapped volumes)                 │
└─────────────────────────────────────────────────────────────────┘
```

## Components

### 1. Collector (host-native)

Runs on the host outside Docker because it needs direct USB access to `/dev/hidraw0`.

- **mpp-solar** Python package ([jblance/mpp-solar](https://github.com/jblance/mpp-solar)) installed in a dedicated virtualenv
- Custom `influx2.py` output plugin writes data to InfluxDB
- Protocol: **PI30** (Easun/Voltronic-compatible inverters)
- Commands collected every minute:
  - `QPIGS` — general status (PV voltage/current/power, battery voltage/current, grid voltage, load, etc.)
  - `QMOD` — device operating mode

**Directory structure:**

```
collector/
├── influx2.py          # custom output plugin (cleaned up, env-var driven)
├── requirements.txt    # mppsolar, influxdb-client
└── setup.sh            # creates venv, installs deps, links output plugin, installs crontab
```

**Crontab entry (installed by setup.sh):**

```cron
* * * * * /opt/solarmon/venv/bin/mpp-solar -P PI30 -p /dev/hidraw0 -c QPIGS -o influx2 && /opt/solarmon/venv/bin/mpp-solar -P PI30 -p /dev/hidraw0 -c QMOD -o influx2
```

**Configuration via environment (sourced from `/opt/solarmon/.env`):**

| Variable | Example | Purpose |
|----------|---------|---------|
| `INFLUXDB_URL` | `http://localhost:8086` | InfluxDB endpoint |
| `INFLUXDB_TOKEN` | `<token>` | InfluxDB API token |
| `INFLUXDB_ORG` | `home` | InfluxDB organization |
| `INFLUXDB_BUCKET` | `solar` | InfluxDB bucket |

### 2. InfluxDB 2.x (Docker)

Time-series database storing all inverter telemetry.

- **Image:** `influxdb:2`
- **Port:** `8086` (bound to host)
- **Persistent data:** `./data/influxdb/` mounted to `/var/lib/influxdb2`
- **Initial setup:** auto-configured on first start via environment variables (org, bucket, admin user/password, token)

**Data schema:**

```
Measurement: easun_3kw
Tags:        sensor=easun_3kw
Fields:      (from QPIGS) grid_voltage, grid_frequency, ac_output_voltage,
             ac_output_frequency, ac_output_apparent_power, ac_output_active_power,
             output_load_percent, bus_voltage, battery_voltage,
             battery_charging_current, battery_capacity, inverter_heat_sink_temperature,
             pv_input_current_for_battery, pv_input_voltage, battery_voltage_from_scc,
             battery_discharge_current, pv_input_power, ...
             (from QMOD) mode
```

### 3. Grafana (Docker)

Visualization dashboards, accessible via browser on the local network.

- **Image:** `grafana:latest`
- **Port:** `3000` (bound to host)
- **Persistent data:** `./data/grafana/` mounted to `/var/lib/grafana`
- **Auto-provisioning:** datasource and default dashboard provisioned via config files on first start

**Provisioned resources:**

```
grafana/
└── provisioning/
    ├── datasources/
    │   └── influxdb.yml    # InfluxDB 2.x datasource (Flux query language)
    └── dashboards/
        ├── dashboards.yml  # dashboard provider config
        └── solar.json      # default dashboard: PV power, battery, grid, load
```

**Default dashboard panels (planned):**

| Panel | Type | Data |
|-------|------|------|
| PV Power (now) | Stat | pv_input_power |
| Load (now) | Stat | ac_output_active_power |
| Battery SOC | Gauge | battery_capacity |
| PV Power (24h) | Time series | pv_input_power |
| Grid / Load / PV | Time series | stacked area |
| Battery Voltage | Time series | battery_voltage |
| Battery Charge/Discharge | Time series | battery_charging_current, battery_discharge_current |
| Inverter Temperature | Time series | inverter_heat_sink_temperature |
| Device Mode | Status | mode |
| Daily Energy Summary | Bar chart | aggregated pv_input_power |

### 4. Restic Backup (Docker)

Automated weekly backup of InfluxDB data to Azure Blob Storage.

- **Image:** custom, based on `restic/restic`
- **Schedule:** weekly on Sunday at 01:00, via cron inside the container
- **What it backs up:** `./data/influxdb/` (mounted read-only)
- **Retention policy:** keep last 8 weekly, 24 monthly snapshots
- **Persistent data:** `./data/restic-cache/` for local cache

**Configuration via environment:**

| Variable | Purpose |
|----------|---------|
| `RESTIC_REPOSITORY` | `azure:solarmon-backup:/` |
| `RESTIC_PASSWORD` | Repo encryption password |
| `AZURE_ACCOUNT_NAME` | Storage account name |
| `AZURE_ACCOUNT_KEY` | Storage account key |

```
backup/
├── Dockerfile
└── backup.sh           # init repo if needed, backup, prune old snapshots
```

## File Layout

```
solarmon/
├── ARCHITECTURE.md          # this file
├── docker-compose.yml       # InfluxDB, Grafana, restic-backup
├── .env.example             # template for all configuration
├── .gitignore               # ignores data/, .env
│
├── collector/               # host-native data collector
│   ├── influx2.py           # cleaned-up InfluxDB 2 output plugin
│   ├── requirements.txt     # mppsolar, influxdb-client
│   └── setup.sh             # install venv, deps, crontab
│
├── backup/
│   ├── Dockerfile
│   └── backup.sh            # restic backup + prune script
│
├── grafana/
│   └── provisioning/
│       ├── datasources/
│       │   └── influxdb.yml
│       └── dashboards/
│           ├── dashboards.yml
│           └── solar.json
│
└── data/                    # gitignored, host-mapped persistent storage
    ├── influxdb/
    ├── grafana/
    └── restic-cache/
```

## Networking

All services communicate over the Docker default bridge network and host-mapped ports.

| Service | Port | Access |
|---------|------|--------|
| InfluxDB | 8086 | Collector (host) → container; Grafana → container |
| Grafana | 3000 | Browser on LAN |

No SSL — private network only.

## Deployment Steps

### Initial setup (one-time)

1. Clone this repo to the target machine
2. Copy `.env.example` to `.env`, fill in:
   - InfluxDB admin credentials and token
   - Azure storage credentials
   - Restic repository password
3. Run `docker compose up -d` — starts InfluxDB, Grafana, restic-backup
4. Run `collector/setup.sh` — creates venv at `/opt/solarmon/`, installs mpp-solar, links influx2 plugin, installs crontab
5. Verify: open `http://<host-ip>:3000` in browser, data should appear within 1 minute

### Redeployment / migration

1. Restore backup: `restic restore latest --target ./data/influxdb/`
2. Follow initial setup steps above
3. Historical data is preserved from the restored backup

### Updates

- **Grafana/InfluxDB:** `docker compose pull && docker compose up -d`
- **mpp-solar:** `source /opt/solarmon/venv/bin/activate && pip install --upgrade mppsolar`

## Backup & Recovery

**Backup chain:**

```
./data/influxdb/ → restic → Azure Blob Storage (encrypted, deduplicated)
```

**Retention:** 8 weekly + 24 monthly snapshots

**Recovery procedure:**

```bash
# List available snapshots
docker compose run restic-backup restic snapshots

# Restore latest snapshot
docker compose stop influxdb
docker compose run restic-backup restic restore latest --target /data/influxdb
docker compose start influxdb
```

Grafana provisioning is stored in the repo (dashboards, datasources), so Grafana data does not need backup — it is reconstructed from the repo on deploy.
