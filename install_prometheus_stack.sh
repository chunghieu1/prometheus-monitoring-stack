#!/bin/bash
set -e

# Check for root privileges
if [ "$EUID" -ne 0 ]; then
  echo "Please run this script as root or with sudo."
  exit 1
fi

echo "=== System update ==="
# Wait for dpkg lock if needed
while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
  echo "Waiting for other package managers to finish..."
  sleep 5
done

# Temporarily suppress kernel upgrade notification
if [ -f /var/run/reboot-required ]; then
  echo "Temporarily removing /var/run/reboot-required to suppress kernel upgrade notification during script run."
  rm -f /var/run/reboot-required
fi

apt update && apt upgrade -y

# --- Prometheus ---
echo "=== Installing Prometheus (latest) ==="
PROM_URL=$(curl -s https://api.github.com/repos/prometheus/prometheus/releases/latest | grep browser_download_url | grep linux-amd64.tar.gz | cut -d '"' -f 4)
PROM_VERSION=$(echo $PROM_URL | grep -oP 'prometheus-\K[0-9.]+')
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
  wget $PROM_URL
  tar -xvf prometheus-$PROM_VERSION.linux-amd64.tar.gz
  mv prometheus-$PROM_VERSION.linux-amd64 prometheus
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
NODE_VERSION=$(echo $NODE_URL | grep -oP 'node_exporter-\K[0-9.]+')
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
  wget $NODE_URL
  tar -xvf node_exporter-$NODE_VERSION.linux-amd64.tar.gz
  mv node_exporter-$NODE_VERSION.linux-amd64 node_exporter
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
GRAFANA_VERSION=$(echo $GRAFANA_URL | grep -oP 'grafana-\K[0-9.]+')
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
  wget $GRAFANA_URL
  tar -xvf grafana-$GRAFANA_VERSION.linux-amd64.tar.gz
  mv grafana-$GRAFANA_VERSION grafana
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
ALERTMANAGER_VERSION=$(echo $ALERT_URL | grep -oP 'alertmanager-\K[0-9.]+')
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
  wget $ALERT_URL
  tar -xvf alertmanager-$ALERTMANAGER_VERSION.linux-amd64.tar.gz
  mv alertmanager-$ALERTMANAGER_VERSION.linux-amd64 alertmanager
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

echo "=== Prometheus Stack installation complete! ==="
echo ""
echo "- If you want to upgrade/reinstall any component, stop the service and remove the corresponding folder/config file before rerunning this script."
echo "- If a service fails, check with systemctl status <service> and review the logs."