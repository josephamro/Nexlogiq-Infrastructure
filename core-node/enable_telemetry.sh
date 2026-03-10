#!/bin/bash

# ==============================================================================
# Telemetry & Monitoring Agent Setup (Opt-In)
# ==============================================================================
# Description: Installs Prometheus Node Exporter and configures UFW to allow
#              the Monitor Node to scrape metrics securely via Tailscale.
# ==============================================================================

if [ "$EUID" -ne 0 ]; then
  echo "[ERROR] Privilege escalation required. Please run as root."
  exit 1
fi

echo "======================================================="
echo "  Telemetry Agent Setup (Node Exporter)"
echo "======================================================="

read -p "Enter the Tailscale IP of your Monitor Node (e.g., 100.x.x.x): " MONITOR_IP

# Validate Tailscale IP format (starts with 100.)
if [[ ! $MONITOR_IP =~ ^100\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "[ERROR] Invalid Tailscale IP. It should start with '100.'"
    exit 1
fi

echo "[INFO] Installing Prometheus Node Exporter..."
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y prometheus-node-exporter

systemctl enable prometheus-node-exporter
systemctl restart prometheus-node-exporter

echo "[INFO] Securing telemetry port (9100) via UFW..."
# Allow incoming traffic only from the Monitor Node via Tailscale interface
ufw allow in on tailscale0 from $MONITOR_IP to any port 9100 comment 'Allow Monitor Node Scrape'
ufw reload

echo "======================================================="
echo "[SUCCESS] Telemetry Agent is LIVE and SECURED!"
echo "[INFO] Your Monitor Node ($MONITOR_IP) can now scrape"
echo "       metrics from this server on port 9100."
echo "======================================================="
