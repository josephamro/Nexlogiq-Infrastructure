#!/bin/bash

# ==============================================================================
# Nexlogiq AI - Out-of-Band Monitoring Node Provisioning (v1.1 Stable)
# ==============================================================================
# Description: Automates the deployment of a secure monitoring server.
# Architecture: Zero-Trust, MFA-Hardened, Optimized for Observability Stack.
# Author: Nexlogiq AI Infrastructure Team
# ==============================================================================

# --- Variables (CHANGE THESE BEFORE RUNNING) ---
USER_NAME="nexlogiq_monitor"
USER_PASS="CHANGE_THIS_TO_A_SECURE_PASSWORD"
SSH_PORT=3333 # CHANGE THIS TO YOUR SECRET PORT FOR THE MONITOR NODE

if [ "$EUID" -ne 0 ]; then
  echo "[ERROR] Privilege escalation required. Please run as root."
  exit 1
fi

echo "[INFO] Initializing Nexlogiq Monitoring Node Provisioning..."

# 1. System Update & Core Dependencies
export DEBIAN_FRONTEND=noninteractive
apt update && apt upgrade -y
apt install -y curl ufw unattended-upgrades libpam-google-authenticator chrony auditd audispd-plugins monit jq

# 2. Automated Security Patching
cat <<EOF > /etc/apt/apt.conf.d/20auto-upgrades
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF
echo "[SUCCESS] Unattended security upgrades configured."

# 3. Time Synchronization & Auditing
systemctl enable chrony && systemctl start chrony
systemctl enable auditd && systemctl start auditd

# 4. User Access Management
useradd -m -s /bin/bash $USER_NAME
echo "$USER_NAME:$USER_PASS" | chpasswd
usermod -aG sudo $USER_NAME

BASE_USER=${SUDO_USER:-ubuntu}
if [ -f "/home/$BASE_USER/.ssh/authorized_keys" ]; then
    mkdir -p /home/$USER_NAME/.ssh
    cp /home/$BASE_USER/.ssh/authorized_keys /home/$USER_NAME/.ssh/
    chown -R $USER_NAME:$USER_NAME /home/$USER_NAME/.ssh
    chmod 700 /home/$USER_NAME/.ssh
    chmod 600 /home/$USER_NAME/.ssh/authorized_keys
fi

# 5. Docker Engine & Log Rotation
curl -fsSL https://get.docker.com | sh
usermod -aG docker $USER_NAME
mkdir -p /etc/docker
cat <<EOF > /etc/docker/daemon.json
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" }
}
EOF
systemctl restart docker

# 6. Systemd Journald Limits (Max 100MB)
sed -i 's/.*SystemMaxUse=.*/SystemMaxUse=100M/' /etc/systemd/journald.conf
systemctl restart systemd-journald

# 7. Zero-Trust Network & CrowdSec
curl -fsSL https://tailscale.com/install.sh | sh
curl -s https://packagecloud.io/install/repositories/crowdsec/crowdsec/script.deb.sh | bash
apt install -y crowdsec crowdsec-firewall-bouncer-iptables

# 8. Firewall Rules (UFW)
ufw default deny incoming
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow $SSH_PORT/tcp
ufw allow in on tailscale0
echo "y" | ufw enable

# 9. SSH Hardening & MFA (FIXED: Enforce Key + Google Auth)
sed -i "s/^#*Port .*/Port $SSH_PORT/" /etc/ssh/sshd_config
sed -i "s/^#*PermitRootLogin .*/PermitRootLogin no/" /etc/ssh/sshd_config
sed -i "s/^#*PasswordAuthentication .*/PasswordAuthentication no/" /etc/ssh/sshd_config
sed -i "s/^#*ChallengeResponseAuthentication .*/ChallengeResponseAuthentication yes/" /etc/ssh/sshd_config
sed -i "s/^#*KbdInteractiveAuthentication .*/KbdInteractiveAuthentication yes/" /etc/ssh/sshd_config

# Force SSH to require BOTH public key and interactive auth (MFA)
if ! grep -q "AuthenticationMethods" /etc/ssh/sshd_config; then
    echo "AuthenticationMethods publickey,keyboard-interactive" >> /etc/ssh/sshd_config
fi

# Add PAM rule (nullok allows first login without MFA to set it up)
if ! grep -q "pam_google_authenticator.so" /etc/pam.d/sshd; then
    echo "auth required pam_google_authenticator.so nullok" >> /etc/pam.d/sshd
fi

# 10. Performance & IPv6 Disable
echo "fs.file-max = 2097152" >> /etc/sysctl.conf
cat <<EOF >> /etc/security/limits.conf
* soft nofile 65535
* hard nofile 65535
root soft nofile 65535
root hard nofile 65535
EOF
echo "net.ipv6.conf.all.disable_ipv6 = 1" >> /etc/sysctl.conf
echo "net.ipv6.conf.default.disable_ipv6 = 1" >> /etc/sysctl.conf

# 11. Memory Optimization (9GB Swap for Extreme Stability on Low-RAM)
if [ ! -f /swapfile ]; then
    echo "[INFO] Allocating 9GB Swap Space..."
    fallocate -l 9G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile && swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
    echo 'vm.swappiness=10' >> /etc/sysctl.conf
fi

# 12. Network Acceleration (TCP BBR)
echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
sysctl -p

# 13. File Integrity Monitoring (Monit)
cat <<EOF >> /etc/monit/monitrc

# Nexlogiq AI Monitoring Rules
set httpd port 2812 and
    use address localhost
    allow localhost

check file passwd with path /etc/passwd
    if changed sha1 checksum then alert
check file sshd_config with path /etc/ssh/sshd_config
    if changed sha1 checksum then alert
check system \$HOST
    if cpu usage > 85% for 5 cycles then alert
    if memory usage > 85% for 5 cycles then alert
check process docker with pidfile /var/run/docker.pid
    start program = "/usr/bin/systemctl start docker"
    stop program = "/usr/bin/systemctl stop docker"
    if failed host 127.0.0.1 port 2375 type tcp then restart
EOF
systemctl restart monit

# ==============================================================================
# 14. Automated Observability Stack Deployment
# ==============================================================================
echo "[INFO] Deploying Observability Stack..."
OBS_DIR="/home/$USER_NAME/observability"
mkdir -p $OBS_DIR/prometheus

# Create targets.json
cat <<EOF > $OBS_DIR/prometheus/targets.json
[]
EOF

# Create prometheus.yml
cat <<EOF > $OBS_DIR/prometheus/prometheus.yml
global:
  scrape_interval: 15s
scrape_configs:
  - job_name: 'prometheus_self'
    static_configs:
      - targets: ['localhost:9090']
  - job_name: 'nexlogiq_core_nodes'
    file_sd_configs:
      - files:
        - '/etc/prometheus/targets.json'
        refresh_interval: 15s
EOF

# Create docker-compose.yml
cat <<EOF > $OBS_DIR/docker-compose.yml
version: '3.8'

services:
  prometheus:
    image: prom/prometheus:latest
    container_name: nexlogiq_prometheus
    volumes:
      - ./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml
      - ./prometheus/targets.json:/etc/prometheus/targets.json
      - prometheus_data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--storage.tsdb.retention.time=7d'
      - '--web.max-connections=20'
    ports:
      - "127.0.0.1:9090:9090"
    restart: unless-stopped
    networks:
      - monitor-net
    deploy:
      resources:
        limits:
          memory: 400M

  grafana:
    image: grafana/grafana:latest
    container_name: nexlogiq_grafana
    volumes:
      - grafana_data:/var/lib/grafana
    environment:
      - GF_SECURITY_ADMIN_USER=admin
      - GF_SECURITY_ADMIN_PASSWORD=nexlogiq_admin
    ports:
      - "3000:3000"
    restart: unless-stopped
    networks:
      - monitor-net
    depends_on:
      - prometheus
    deploy:
      resources:
        limits:
          memory: 300M

  uptime-kuma:
    image: louislam/uptime-kuma:1
    container_name: nexlogiq_uptime_kuma
    volumes:
      - uptime-kuma_data:/app/data
    ports:
      - "3001:3001"
    restart: unless-stopped
    networks:
      - monitor-net
    deploy:
      resources:
        limits:
          memory: 200M

networks:
  monitor-net:
    driver: bridge

volumes:
  prometheus_data:
  grafana_data:
  uptime-kuma_data:
EOF

# FIX: Grant Prometheus user (UID 65534) access to read the targets file
chown -R 65534:65534 $OBS_DIR/prometheus
chmod -R 755 $OBS_DIR/prometheus
chown $USER_NAME:$USER_NAME $OBS_DIR/docker-compose.yml

# FIX: Wait for Docker daemon to fully initialize before composing
echo "[INFO] Waiting for Docker daemon to stabilize..."
sleep 10

cd $OBS_DIR
docker compose up -d
echo "[SUCCESS] Observability Stack is running!"

# ==============================================================================
# 15. Restricted Enterprise MOTD Branding
# ==============================================================================
chmod -x /etc/update-motd.d/* 2>/dev/null
cat << 'EOF' > /etc/update-motd.d/99-nexlogiq
#!/bin/sh
echo "========================================================================"
echo "  _    _ _______   ___        ____   _____ _____  ___         /\    |_   _| "
echo " | \ | |  ___\ \ / / |      / __ \ / ____|_   _|/ _ \       /  \    | |   "
echo " |  \| | |__  \ V /| |     | |  | | |  __  | | | | | |     / /\ \   | |   "
echo " | . \` |  __|  > < | |     | |  | | | |_ | | | | | | |    / ____ \  | |   "
echo " | |\  | |____/ . \| |____| |__| | |__| |_| |_| |_| |   /_/    \_\_| |_  "
echo " |_| \_|______/_/ \_\______\____/ \_____|____ |\__\_\            |_____| "
echo "========================================================================"
echo "[WARNING]  UNAUTHORIZED ACCESS. THIS IS A RESTRICTED OOB MONITORING NODE."
echo "[SECURITY] INFRASTRUCTURE HARDENED & PROVISIONED BY NEXLOGIQ AI."
echo "[AUDIT]    ALL ACTIVITIES ARE LOGGED AND MONITORED (ZERO-TRUST NODE)."
echo "========================================================================"
EOF
chmod +x /etc/update-motd.d/99-nexlogiq

echo "[INFO] Monitoring Node Provisioning complete. Rebooting in 5 seconds..."
sleep 5
reboot
