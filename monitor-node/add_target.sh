#!/bin/bash

# ==============================================================================
# Dynamic Target Addition for Prometheus
# ==============================================================================
# Description: Adds a new core node to the Prometheus File-Based Service
#              Discovery (targets.json) without restarting the container.
# Dependencies: jq
# ==============================================================================

# --- Variables (CHANGE THESE IF NECESSARY) ---
# Replace 'your_user' with the actual non-root username running the monitor stack
TARGET_USER="your_user"
TARGET_FILE="/home/$TARGET_USER/observability/prometheus/targets.json"

echo "======================================================="
echo "  Add New Core Node to Prometheus Monitoring"
echo "======================================================="

# Ensure jq is installed
if ! command -v jq &> /dev/null; then
    echo "[ERROR] 'jq' is not installed. Please install it first: apt-get install jq"
    exit 1
fi

read -p "Enter the Tailscale IP of the new server (e.g., 100.x.x.x): " NODE_IP
read -p "Enter a friendly name for this server (e.g., prod-core-01): " NODE_NAME

# Initialize the JSON file if it doesn't exist
if [ ! -f "$TARGET_FILE" ]; then
    echo "[INFO] Target file not found. Creating a new one at $TARGET_FILE..."
    mkdir -p "$(dirname "$TARGET_FILE")"
    echo "[]" > "$TARGET_FILE"
    chown $TARGET_USER:$TARGET_USER "$TARGET_FILE"
fi

echo "[INFO] Updating $TARGET_FILE..."

# Safely append the new target using jq
jq ". += [{\"targets\": [\"$NODE_IP:9100\"], \"labels\": {\"server_name\": \"$NODE_NAME\"}}]" "$TARGET_FILE" > tmp.json && mv tmp.json "$TARGET_FILE"

# Fix permissions in case the script is run with sudo
chown $TARGET_USER:$TARGET_USER "$TARGET_FILE"

echo "======================================================="
echo "[SUCCESS] Added $NODE_NAME ($NODE_IP) to monitoring targets."
echo "[INFO] Prometheus will detect this automatically within 15 seconds."
echo "======================================================="
