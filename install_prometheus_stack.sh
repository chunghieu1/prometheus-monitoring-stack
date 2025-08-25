#!/bin/bash
set -e

LOG_FILE="/var/log/prometheus_stack_install.log"
exec > >(tee -a "$LOG_FILE") 2>&1

# Check for root privileges
if [ "$EUID" -ne 0 ]; then
  echo "Please run this script as root or with sudo."
  exit 1
fi

# 1. Detect and disable firewalls (csf, ufw, firewalld)
echo "=== Checking and disabling firewalls (csf, ufw, firewalld) ==="
if systemctl is-active --quiet csf; then
  echo "Disabling csf firewall..."
  systemctl stop csf || true
  systemctl disable csf || true
fi
if systemctl is-active --quiet ufw; then
  echo "Disabling ufw firewall..."
  ufw disable || true
  systemctl stop ufw || true
  systemctl disable ufw || true
fi
if systemctl is-active --quiet firewalld; then
  echo "Disabling firewalld..."
  systemctl stop firewalld || true
  systemctl disable firewalld || true
fi

# 2. Temporarily suppress kernel upgrade notification
if [ -f /var/run/reboot-required ]; then
  echo "Temporarily removing /var/run/reboot-required to suppress kernel upgrade notification during script run."
  rm -f /var/run/reboot-required
fi

# 3. System update (wait for dpkg lock)
while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
  echo "Waiting for other package managers to finish..."
  sleep 5
done
export DEBIAN_FRONTEND=noninteractive
apt update && apt upgrade -y

# 4. Ensure data directories exist
echo "Ensuring data directories exist..."
mkdir -p /opt/prometheus/data /opt/alertmanager/data

# 5. Check config file write permissions
for f in /opt/prometheus/prometheus.yml /opt/alertmanager/alertmanager.yml; do
  if [ -e "$f" ] && [ ! -w "$f" ]; then
    echo "ERROR: Cannot write to $f. Please check permissions."
    exit 1
  fi
  # If file does not exist, check parent dir
  if [ ! -e "$f" ] && [ ! -w "$(dirname $f)" ]; then
    echo "ERROR: Cannot write to $(dirname $f). Please check permissions."
    exit 1
  fi
done

# --- Prometheus ---
echo "=== Installing Prometheus (latest) ==="
PROM_URL=$(curl -s https://api.github.com/repos/prometheus/prometheus/releases/latest | grep browser_download_url | grep linux-amd64.tar.gz | cut -d '"' -f 4)
PROM_SERVICE=prometheus
if systemctl list-unit-files | grep -q "^$PROM_SERVICE"; then
  if systemctl is-active --quiet $PROM_SERVICE; then
    echo "Prometheus service is already running."
    echo "If you want to upgrade or reinstall, please stop the service and remove /opt/prometheus before rerunning this script."
  else
    echo "Prometheus is installed but stopped or failed. Check: systemctl status prometheus."
    echo "This script does not auto-fix service errors."
  fi
else
  cd /opt
  PROM_FILE=$(basename "$PROM_URL")
  wget -O "$PROM_FILE" "$PROM_URL" && \
  tar -xvf "$PROM_FILE" && \
  PROM_DIR=$(tar -tf "$PROM_FILE" | head -1 | cut -f1 -d"/") && \
  mv "$PROM_DIR" prometheus
  cat <<EOF > /etc/systemd/system/prometheus.service
[Unit]
Description=Prometheus
After=network.target

[Service]
User=root
ExecStart=/opt/prometheus/prometheus \
  --config.file=/opt/prometheus/prometheus.yml \
  --storage.tsdb.path=/opt/prometheus/data

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable prometheus
  systemctl start prometheus
  echo "Prometheus is running at: http://localhost:9090"
fi

# --- Node Exporter ---
echo "=== Installing Node Exporter (latest) ==="
NODE_URL=$(curl -s https://api.github.com/repos/prometheus/node_exporter/releases/latest | grep browser_download_url | grep linux-amd64.tar.gz | cut -d '"' -f 4)
NODE_EXPORTER_SERVICE=node_exporter
if systemctl list-unit-files | grep -q "^$NODE_EXPORTER_SERVICE"; then
  if systemctl is-active --quiet $NODE_EXPORTER_SERVICE; then
    echo "Node Exporter service is already running."
    echo "If you want to upgrade or reinstall, please stop the service and remove /opt/node_exporter before rerunning this script."
  else
    echo "Node Exporter is installed but stopped or failed. Check: systemctl status node_exporter."
    echo "This script does not auto-fix service errors."
  fi
else
  cd /opt
  NODE_FILE=$(basename "$NODE_URL")
  wget -O "$NODE_FILE" "$NODE_URL" && \
  tar -xvf "$NODE_FILE" && \
  NODE_DIR=$(tar -tf "$NODE_FILE" | head -1 | cut -f1 -d"/") && \
  mv "$NODE_DIR" node_exporter
  cat <<EOF > /etc/systemd/system/node_exporter.service
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=root
ExecStart=/opt/node_exporter/node_exporter

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable node_exporter
  systemctl start node_exporter
  echo "Node Exporter is running at: http://localhost:9100"
fi

# --- Grafana ---
echo "=== Installing Grafana (latest) ==="
GRAFANA_URL=$(curl -s https://api.github.com/repos/grafana/grafana/releases/latest | grep browser_download_url | grep linux-amd64.tar.gz | cut -d '"' -f 4)
GRAFANA_SERVICE=grafana-server
if systemctl list-unit-files | grep -q "^$GRAFANA_SERVICE"; then
  if systemctl is-active --quiet $GRAFANA_SERVICE; then
    echo "Grafana service is already running."
    echo "If you want to upgrade or reinstall, please stop the service and remove /opt/grafana before rerunning this script."
  else
    echo "Grafana is installed but stopped or failed. Check: systemctl status grafana-server."
    echo "This script does not auto-fix service errors."
  fi
else
  cd /opt
  GRAFANA_FILE=$(basename "$GRAFANA_URL")
  wget -O "$GRAFANA_FILE" "$GRAFANA_URL" && \
  tar -xvf "$GRAFANA_FILE" && \
  GRAFANA_DIR=$(tar -tf "$GRAFANA_FILE" | head -1 | cut -f1 -d"/") && \
  mv "$GRAFANA_DIR" grafana
  useradd --no-create-home --shell /bin/false grafana || true
  cat <<EOF > /etc/systemd/system/grafana-server.service
[Unit]
Description=Grafana instance
After=network.target

[Service]
User=grafana
Group=grafana
Type=simple
ExecStart=/opt/grafana/bin/grafana-server --homepath=/opt/grafana
Restart=always

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable grafana-server
  systemctl start grafana-server
  echo "Grafana is running at: http://localhost:3000 (default user/pass: admin/admin)"
fi

# --- Alertmanager ---
echo "=== Installing Alertmanager (latest) ==="
ALERT_URL=$(curl -s https://api.github.com/repos/prometheus/alertmanager/releases/latest | grep browser_download_url | grep linux-amd64.tar.gz | cut -d '"' -f 4)
ALERTMANAGER_SERVICE=alertmanager
if systemctl list-unit-files | grep -q "^$ALERTMANAGER_SERVICE"; then
  if systemctl is-active --quiet $ALERTMANAGER_SERVICE; then
    echo "Alertmanager service is already running."
    echo "If you want to upgrade or reinstall, please stop the service and remove /opt/alertmanager before rerunning this script."
  else
    echo "Alertmanager is installed but stopped or failed. Check: systemctl status alertmanager."
    echo "This script does not auto-fix service errors."
  fi
else
  cd /opt
  ALERT_FILE=$(basename "$ALERT_URL")
  wget -O "$ALERT_FILE" "$ALERT_URL" && \
  tar -xvf "$ALERT_FILE" && \
  ALERT_DIR=$(tar -tf "$ALERT_FILE" | head -1 | cut -f1 -d"/") && \
  mv "$ALERT_DIR" alertmanager
  cat <<EOF > /opt/alertmanager/alertmanager.yml
global:
  resolve_timeout: 5m

route:
  receiver: 'discord'

receivers:
  - name: 'discord'
    webhook_configs:
      - url: 'http://localhost:9094'
        send_resolved: true
EOF
  cat <<EOF > /etc/systemd/system/alertmanager.service
[Unit]
Description=Alertmanager
After=network.target

[Service]
User=root
ExecStart=/opt/alertmanager/alertmanager \
  --config.file=/opt/alertmanager/alertmanager.yml \
  --storage.path=/opt/alertmanager/data \
  --cluster.listen-address=""

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable alertmanager
  systemctl start alertmanager
  echo "Alertmanager is running at: http://localhost:9093"
fi

# After installing Grafana, ensure Prometheus scrapes Grafana metrics
PROM_CONFIG="/opt/prometheus/prometheus.yml"
if ! grep -q 'job_name:.*grafana' "$PROM_CONFIG"; then
  echo "Adding Grafana scrape job to prometheus.yml..."
  cat <<EOG >> "$PROM_CONFIG"

  - job_name: "grafana"
    static_configs:
      - targets: ["localhost:3000"]
EOG
  systemctl reload prometheus || systemctl restart prometheus
  echo "Prometheus config updated to scrape Grafana metrics."
fi

# 6. Check service status after start
for svc in prometheus node_exporter grafana-server alertmanager; do
  if ! systemctl is-active --quiet $svc; then
    echo "ERROR: $svc failed to start. Showing last 20 log lines:"
    journalctl -u $svc --no-pager -n 20
  fi
  echo "$svc is running."
done

# 7. Notify if reboot is required after install
if [ -f /var/run/reboot-required ]; then
  echo "WARNING: System reboot is required to complete kernel upgrade. Please reboot soon."
fi

# Detect public IPv4 address
IPV4=$(curl -s http://checkip.amazonaws.com || hostname -I | awk '{print $1}')

cat <<EOF

=== Access the stack ===
Prometheus:   http://$IPV4:9090
Node Exporter: http://$IPV4:9100
Grafana:      http://$IPV4:3000 (default user/pass: admin/admin)
Alertmanager: http://$IPV4:9093

Replace '$IPV4' with your VPS public IP address if accessing from another device.
EOF

echo "=== Prometheus Stack installation complete! ==="
echo "- If you want to upgrade/reinstall any component, stop the service and remove the corresponding folder/config file before rerunning this script."
echo "- If a service fails, check with systemctl status <service> and review the logs."
echo "- Install log saved at $LOG_FILE."