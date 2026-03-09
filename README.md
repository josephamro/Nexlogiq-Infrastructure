# Nexlogiq AI - Enterprise Distributed Infrastructure Blueprint

An automated, enterprise-grade Infrastructure as Code (IaC) repository designed to provision, harden, and optimize Linux-based Virtual Private Servers (VPS). Engineered by the **Nexlogiq AI Infrastructure Team**, this blueprint establishes a highly secure, distributed architecture that splits critical application workloads from observability stacks.

---

## 1. Architecture Overview

This infrastructure strictly adheres to the **NIST SP 800-207 Zero-Trust architecture** and **CIS Benchmarks** for Linux system hardening. It assumes the public internet is a hostile environment and removes reliance on traditional perimeter-only defenses.

The repository is divided into two distinct node types:

* **`core-node`**: The primary engine for databases, AI agents, and production applications (e.g., Coolify). Optimized for heavy workloads with an 8GB Swap allocation, TCP BBR network acceleration, and self-healing mechanisms.
* **`monitor-node`**: An isolated Out-of-Band (OOB) server. Connects to the core node securely via an encrypted tunnel to collect metrics without exposing telemetry to the public internet.

---

## 2. Core Defense & Performance Features

### Security & Auditing
* **Active Defense:** CrowdSec analyzes behavioral patterns and automatically blocks malicious IPs via `iptables`.
* **Strict Authentication:** Disables root login and password authentication entirely. Enforces SSH Key pairs combined with Google Authenticator (PAM) for mandatory Multi-Factor Authentication (MFA).
* **System Auditing:** Uses `auditd` to act as a "black box," logging all root-level commands.
* **Integrity Monitoring:** `Monit` actively watches critical files (`/etc/passwd`, `/etc/ssh/sshd_config`) and alerts on unauthorized SHA1 checksum changes.

### Performance Optimization
* **Concurrency:** Raises system file descriptor limits (`fs.file-max`) to 65,535 for high-traffic handling.
* **Throughput:** Enables Google's TCP BBR algorithm to reduce latency.
* **Resource Protection:** Strict log rotation limits for Docker (max 10MB) and Systemd Journald (max 100MB) to prevent Out-Of-Space crashes.

---

## 3. Advanced Operational Tactics (OpSec)

### The "Invisible Node" Strategy
While the OS-level firewall (UFW) allows the custom SSH port, **the Cloud Provider's Firewall (VCN Security Lists) must be configured to DROP all incoming SSH traffic from the public internet (0.0.0.0/0).**

By doing this:
1. The server becomes completely invisible to automated port scanners and botnets.
2. Administrative SSH access is **only possible** by pinging the internal Tailscale VPN IP (e.g., `100.x.x.x`).

### Emergency "Break-Glass" Procedure
1. Log into the Cloud Provider Console (Oracle Cloud / AWS).
2. Temporarily open the custom SSH port in the VCN Security Group.
3. SSH into the server using the **Public IP** to resolve the issue.
4. Immediately close the VCN port once restored.

---

## 4. Application Layer & Disaster Recovery (DR)

The `core-node` is pre-optimized to host **Coolify**.

### High Availability via S3
1. **Infrastructure as Code:** Reconstruct the secure OS layer in under 5 minutes using this script.
2. **State Management:** Automated, encrypted backups to an external **S3-compatible Object Storage Bucket** (Cloudflare R2 or AWS S3).
3. **Restoration:** Spin up a new node, install Coolify, and pull the latest S3 snapshot for seamless recovery.

---

## 5. Step-by-Step Deployment Guide

### Prerequisites
1. Fresh installation of **Ubuntu 22.04 or 24.04**.
2. Root (`sudo`) access.
3. Active [Tailscale](https://tailscale.com/) account.
4. Google Authenticator app on your mobile device.

### Phase 1: Preparation & Execution

1. **Clone the repository:**
   ```bash
   git clone https://github.com/nexlogiqai/Nexlogiq-Infrastructure.git
   cd Nexlogiq-Infrastructure
   ```

2. **Edit variables in your script:**
   ```bash
   # Edit core-node/provision_core.sh
   USER_NAME="nexlogiq_admin"
   USER_PASS="your_secure_password"
   SSH_PORT=2222
   ```

3. **Execute the script:**
   ```bash
   sudo bash core-node/provision_core.sh
   ```

### Phase 2: Post-Deployment Initialization (CRITICAL)

**Step 1: First-Time Login (Public IP)**
Login using your **Public IP** and **SSH Key**. The script allows a one-time login without MFA via `nullok`:
```bash
ssh -i /path/to/private_key -p <YOUR_PORT> <USER_NAME>@<PUBLIC_IP>
```

**Step 2: Setup MFA**
Immediately run:
```bash
google-authenticator
```
*(Answer **y** to all prompts, scan QR code, and save backup codes).*

**Step 3: Activate Zero-Trust VPN**
```bash
sudo tailscale up
```

**Step 4: The "Invisible" Switch**
Go to Cloud Console and **DELETE** the Port Ingress Rule for SSH. Access is now Tailscale only.

---

## 6. System Verification Commands

```bash
# Check Firewall Rules
sudo ufw status numbered

# Check Active Threat Defense
sudo cscli metrics

# Check Integrity & Health Status
sudo monit status

# Check Docker Daemon Logging
docker info | grep "Logging Driver"
```

---
**Maintained by Nexlogiq AI** | Infrastructure Engineering Division
