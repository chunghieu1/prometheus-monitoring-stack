#!/bin/bash
set -e

# Check for root privileges
if [ "$EUID" -ne 0 ]; then
  echo "Please run this script as root or with sudo."
  exit 1
fi

echo "=== System update ==="
apt update && apt upgrade -y

# --- Prometheus ---
PROM_VERSION="2.53.2"
PROM_SERVICE=prometheus
echo "=== Installing Prometheus ==="
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
  wget https://github.com/prometheus/prometheus/releases/download/v$PROM_VERSION/prometheus-$PROM_VERSION.linux-amd64.tar.gz
  tar -xvf prometheus-$PROM_VERSION.linux-amd64.tar.gz
  mv prometheus-$PROM_VERSION.linux-amd64 prometheus
  cat <<EOF > /etc/systemd/system/prometheus.service
[Unit]
Description=Prometheus
After=network.target

[Service]
User=root
ExecStart=/opt/prometheus/prometheus \\
  --config.file=/opt/prometheus/prometheus.yml \\
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
NODE_EXPORTER_VERSION="1.8.2"
NODE_EXPORTER_SERVICE=node_exporter
echo "=== Installing Node Exporter ==="
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
  wget https://github.com/prometheus/node_exporter/releases/download/v$NODE_EXPORTER_VERSION/node_exporter-$NODE_EXPORTER_VERSION.linux-amd64.tar.gz
  tar -xvf node_exporter-$NODE_EXPORTER_VERSION.linux-amd64.tar.gz
  mv node_exporter-$NODE_EXPORTER_VERSION.linux-amd64 node_exporter
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
GRAFANA_SERVICE=grafana-server
echo "=== Installing Grafana ==="
if systemctl list-unit-files | grep -q "^$GRAFANA_SERVICE"; then
  if systemctl is-active --quiet $GRAFANA_SERVICE; then
    echo "Grafana service is already running."
    echo "If you want to upgrade or reinstall, please stop the service and uninstall grafana before rerunning this script."
  else
    echo "Grafana is installed but stopped or failed. Check: systemctl status grafana-server."
    echo "This script does not auto-fix service errors."
  fi
else
  apt-get update
  apt-get install -y apt-transport-https software-properties-common wget
  wget -q -O - https://packages.grafana.com/gpg.key | apt-key add -
  echo "deb https://packages.grafana.com/oss/deb stable main" | tee /etc/apt/sources.list.d/grafana.list
  apt-get update
  apt-get install grafana -y
  systemctl enable grafana-server
  systemctl start grafana-server
  echo "Grafana is running at: http://localhost:3000 (default user/pass: admin/admin)"
fi

# --- Alertmanager ---
ALERTMANAGER_VERSION="0.27.0"
ALERTMANAGER_SERVICE=alertmanager
echo "=== Installing Alertmanager ==="
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
  wget https://github.com/prometheus/alertmanager/releases/download/v$ALERTMANAGER_VERSION/alertmanager-$ALERTMANAGER_VERSION.linux-amd64.tar.gz
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
ExecStart=/opt/alertmanager/alertmanager \\
  --config.file=/opt/alertmanager/alertmanager.yml \\
  --storage.path=/opt/alertmanager/data

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable alertmanager
  systemctl start alertmanager
  echo "Alertmanager is running at: http://localhost:9093"
fi

echo "=== Prometheus Stack installation complete! ==="
echo ""
echo "- If you want to upgrade/reinstall any component, stop the service and remove the corresponding folder/config file before rerunning this script."
echo "- If a service fails, check with systemctl status <service> and review the logs."