# Prometheus Monitoring Stack Auto Installer

A fully automated script to install Prometheus, Node Exporter, Grafana, and Alertmanager on Ubuntu. No manual steps, no config files to edit — just run and go.

## Features

- Silent and unattended setup
- Automatically installs all dependencies
- Sets up Prometheus, Node Exporter, Grafana, and Alertmanager as systemd services
- Auto-configures Alertmanager for Discord webhook
- Works out-of-the-box on Ubuntu VPS (20.04+)
- Skips installation if service already exists
- Detects and warns if service is stopped or failed

## Requirements

- Ubuntu-based server (20.04 or later)
- Root or sudo privileges
- Internet connection

## Usage

### 1. Clone the repository

```bash
git clone https://github.com/chunghieu1/prometheus-monitoring-stack.git
cd prometheus-monitoring-stack
```

### 2. Run the installation script

```bash
chmod +x install_prometheus_stack.sh
sudo ./install_prometheus_stack.sh
```

This script will:

- Install all required packages
- Set up Prometheus, Node Exporter, Grafana, and Alertmanager
- Configure Alertmanager for Discord integration
- Start all services and enable them on boot
- Skip any service that is already running

### 3. Run directly using curl (optional)

You can skip cloning and run the script directly:

```bash
bash <(curl -sSL https://raw.githubusercontent.com/chunghieu1/prometheus-monitoring-stack/main/install_prometheus_stack.sh)
```

### 4. Access the stack

- **Prometheus:** http://your-server-ip:9090
- **Node Exporter:** http://your-server-ip:9100
- **Grafana:** http://your-server-ip:3000 (default user/pass: admin/admin)
- **Alertmanager:** http://your-server-ip:9093

Replace `your-server-ip` with your VPS public IP address.

## Default Configuration

- **Prometheus config:** `/opt/prometheus/prometheus.yml`
- **Node Exporter:** runs on port 9100
- **Grafana:** runs on port 3000

## Notes

- You can edit the config files in `/opt/prometheus` and `/opt/alertmanager` to customize later.
- Make sure to open ports 9090, 9100, 3000, 9093, 9094 in your VPS firewall/security group.
- For advanced customization, refer to the official documentation of each component.

---

**Enjoy your monitoring stack!**

---

## License

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
