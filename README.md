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

This blueprint utilizes a dual-layer firewall strategy designed for extreme environments (like Oracle Cloud, AWS, or GCP).

### The "Invisible Node" Strategy
While the OS-level firewall (UFW) is configured by the script to *allow* the custom SSH port, **the Cloud Provider's Firewall (e.g., Oracle VCN Security Lists) must be configured to DROP all incoming SSH traffic from the public internet (0.0.0.0/0).**


By doing this:
1. The server becomes completely invisible to automated port scanners and botnets.
2. Administrative SSH access is **only possible** by pinging the internal Tailscale VPN IP (e.g., `100.x.x.x`).

### Emergency "Break-Glass" Procedure
In the event of a catastrophic VPN failure where Tailscale goes down globally, administrators are not locked out. The "Break-Glass" recovery process is simple:
1. Log into the Cloud Provider Console (Oracle Cloud / AWS).
2. Temporarily open the custom SSH port in the Virtual Cloud Network (VCN) Security Group.
3. SSH into the server using the **Public IP** to resolve the VPN issue.
4. Immediately close the VCN port once the VPN is restored to return to the "Invisible" state.

---

## 4. Application Layer & Disaster Recovery (DR)

The `core-node` is intentionally engineered as a sterile environment, pre-optimized to host **Coolify** (an open-source, self-hosted Heroku alternative). 

### High Availability via S3
To ensure zero data loss and minimal Recovery Time Objective (RTO):
1. **Infrastructure as Code:** If a server burns down, this script reconstructs the secure OS layer in under 5 minutes.
2. **State Management:** Coolify and all containerized application databases are configured to run automated, encrypted backups to an external **S3-compatible Object Storage Bucket** (e.g., Cloudflare R2 or AWS S3).
3. **Restoration:** In a disaster scenario, spinning up a new node via this script, installing Coolify, and pulling the latest S3 snapshot restores the entire corporate infrastructure seamlessly.

---

## 5. Step-by-Step Deployment Guide

### Prerequisites
1. A fresh, unmodified installation of **Ubuntu 22.04 or 24.04**.
2. Root (`sudo`) access to the server.
3. An active [Tailscale](https://tailscale.com/) account.
4. The Google Authenticator app installed on your mobile device.

### Phase 1: Preparation & Execution

1. Clone the repository to your server:
   ```bash
   git clone (https://github.com/nexlogiqai/Nexlogiq-Infrastructure.git)
   cd Nexlogiq-Infrastructure

```

2. Edit the variables at the top of your chosen script (`core-node/provision_core.sh` or `monitor-node/provision_monitor.sh`):
```bash
USER_NAME="nexlogiq_admin"
USER_PASS="your_very_secure_password"
SSH_PORT=2222 # Choose a non-standard port (e.g., 4422, 5022)

```


3. Execute the script with root privileges:
```bash
sudo bash core-node/provision_core.sh

```



### Phase 2: Post-Deployment Initialization (CRITICAL)

**Step 1: First-Time Login (Public IP)**
After the reboot, login for the first time using the **Public IP** and your **SSH Private Key**. The script allows a one-time login without MFA via the `nullok` policy:

```bash
ssh -i /path/to/your/private_key.key -p <YOUR_CUSTOM_PORT> <USER_NAME>@<SERVER_PUBLIC_IP>

```

**Step 2: Setup Multi-Factor Authentication (MFA)**
Immediately initialize your secondary security layer:

```bash
google-authenticator

```

*(Answer **y** to all prompts, scan the QR code with your phone, and **securely store** the backup scratch codes).*

**Step 3: Connect to the Private Network (Tailscale)**
Authenticate the server to your Zero-Trust network:

```bash
sudo tailscale up

```

*(Follow the generated URL to authorize the node in your Tailscale admin console).*

**Step 4: The "Invisible" Switch**
Now that you are connected via VPN, go to your Cloud Provider (Oracle/AWS) and **DELETE** the Port Ingress Rule for `<YOUR_CUSTOM_PORT>`. Access is now restricted to Tailscale only.

---

## 6. System Verification Commands

Verify the integrity of your newly provisioned node:

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

## Legal & Security Disclaimer

This script executes deep system modifications, alters firewall rules, disables default networking protocols (IPv6), and changes authentication mechanisms. **It is strongly advised to read the source code in its entirety before deploying it in a production environment.** Unauthorized access to nodes provisioned utilizing this architecture is strictly prohibited. All activities are actively logged by `auditd`.

---

**Maintained by Nexlogiq AI** | Infrastructure Engineering Division
