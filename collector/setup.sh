#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="/opt/solarmon"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VENV_DIR="$INSTALL_DIR/venv"
ENV_FILE="$INSTALL_DIR/.env"
CRON_FILE="/etc/cron.d/solarmon"

echo "==> Creating install directory $INSTALL_DIR"
sudo mkdir -p "$INSTALL_DIR"

echo "==> Creating Python virtualenv at $VENV_DIR"
sudo python3 -m venv "$VENV_DIR"

echo "==> Installing Python dependencies"
sudo "$VENV_DIR/bin/pip" install --upgrade pip
sudo "$VENV_DIR/bin/pip" install -r "$REPO_DIR/collector/requirements.txt"

# Link the custom influx2 output plugin into the mppsolar outputs directory
OUTPUTS_DIR=$("$VENV_DIR/bin/python3" -c "import mppsolar.outputs; import os; print(os.path.dirname(mppsolar.outputs.__file__))")
echo "==> Linking influx2.py into $OUTPUTS_DIR"
sudo ln -sf "$REPO_DIR/collector/influx2.py" "$OUTPUTS_DIR/influx2.py"

# Copy .env from the repo if one doesn't exist yet
if [ ! -f "$ENV_FILE" ]; then
    echo "==> Copying .env.example to $ENV_FILE"
    sudo cp "$REPO_DIR/.env.example" "$ENV_FILE"
    echo "    *** Edit $ENV_FILE and fill in your credentials ***"
else
    echo "==> $ENV_FILE already exists, skipping"
fi

# Install crontab
echo "==> Installing cron job at $CRON_FILE"
sudo tee "$CRON_FILE" > /dev/null <<CRON
# Solarmon: collect inverter data every minute
SHELL=/bin/bash
* * * * * root . $ENV_FILE && $VENV_DIR/bin/mpp-solar -P PI30 -p /dev/hidraw0 -c QPIGS -o influx2 && $VENV_DIR/bin/mpp-solar -P PI30 -p /dev/hidraw0 -c QMOD -o influx2
CRON
sudo chmod 644 "$CRON_FILE"

echo ""
echo "==> Done!"
echo "    1. Edit $ENV_FILE with your InfluxDB credentials"
echo "    2. Verify the inverter is at /dev/hidraw0"
echo "    3. Data collection starts automatically via cron"
