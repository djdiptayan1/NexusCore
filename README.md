<div align="center">

[![Ubuntu Version](https://img.shields.io/badge/Ubuntu-24.04.2_LTS-orange.svg)](https://ubuntu.com/)
[![Bash Script](https://img.shields.io/badge/Bash-Script-brightgreen.svg)](https://www.gnu.org/software/bash/)
[![Version](https://img.shields.io/badge/Version-3.2-blue.svg)](https://github.com/djdiptayan1/NexusCore)

</div>
<!-- # NexusCore - Ubuntu Server Setup Toolkit -->

<div align="center">
<pre style="color:#32CD32; font-weight:bold; text-align:center;">
 ███    ██ ███████ ██   ██ ██    ██ ███████  ██████  ██████  ██████  ███████ 
 ████   ██ ██       ██ ██  ██    ██ ██      ██      ██    ██ ██   ██ ██      
 ██ ██  ██ █████     ███   ██    ██ ███████ ██      ██    ██ ██████  █████   
 ██  ██ ██ ██       ██ ██  ██    ██      ██ ██      ██    ██ ██   ██ ██      
██   ████ ███████ ██   ██  ██████  ███████  ██████  ██████  ██   ██ ███████
</pre>
</div>

> A complete Ubuntu 24.04 LTS server provisioning toolkit with interactive setup

## 📋 Overview

NexusCore is a complete server setup script for Ubuntu 24.04 LTS. It uses interactive prompts to let you choose exactly what to install — perfect for first-time setup of bare metal servers, VPS instances (Hostinger, DigitalOcean, etc.), or any fresh Ubuntu server.

## 🔧 Features

### Interactive Setup
- ✅ Choose what to install at runtime via simple yes/no prompts
- ✅ Single-user focused setup (uses current user)
- ✅ Organized prompts in categories: Server Config, Development Tools, Server Software
- ✅ Summary confirmation before proceeding

### Resilient Execution
- ✅ **Isolated components** — failure in one component doesn't stop the rest
- ✅ **Already-installed detection** — skips Go, Docker, Cloudflared, swap, etc. if already present
- ✅ **apt retry logic** — automatically retries if apt is locked by another process
- ✅ **Setup summary** — shows succeeded ✓, skipped →, and failed ✗ components at the end
- ✅ **Re-runnable** — safe to run again; it picks up where it left off

### Server Configuration
- ✅ Custom hostname configuration
- ✅ Timezone setup
- ✅ Swap file creation (configurable size, recommended for VPS)
- ✅ SSH hardening (disable root login, password auth toggle, max auth tries)
- ✅ UFW (Uncomplicated Firewall) setup
- ✅ Automatic security updates (unattended-upgrades)
- ✅ Fail2ban for SSH brute-force protection

### Development Environment
- ✅ Multiple programming languages and runtimes:
  - Python 3 with pip, venv, and dev headers
  - OpenJDK 17 (JDK & JRE)
  - Go (Golang)
  - C/C++ toolchain (gcc, g++, gdb, clang)
  - Node.js LTS via NVM (Node Version Manager)
- ✅ Miniconda for Python environment management
- ✅ Docker and Docker Compose

### Server Software
- ✅ Nginx web server
- ✅ Cloudflared for Cloudflare Tunnel setup

### Monitoring & Diagnostics
- ✅ System monitoring: htop, btop, glances, bpytop, nload
- ✅ I/O monitoring: iotop, iftop, sysstat
- ✅ Hardware sensors: lm-sensors
- ✅ Disk analysis: ncdu
- ✅ Network diagnostics: mtr, nload, net-tools, dnsutils

### Essential Server Tools (Always Installed)
- ✅ Session management: tmux, screen
- ✅ Editors: vim, nano
- ✅ Utilities: jq, rsync, socat, tree, ncdu, pass
- ✅ System: logrotate, cron, sysstat

## 🚀 Quick Start

### Prerequisites
- A clean Ubuntu 24.04.2 LTS installation
- A user account with sudo privileges

### Installation

1. Clone this repository:
   ```bash
   git clone https://github.com/djdiptayan1/NexusCore.git
   cd NexusCore
   ```

2. Make the script executable:
   ```bash
   chmod +x setup_nexuscore.sh
   ```

3. Run the script:
   ```bash
   ./setup_nexuscore.sh
   ```

4. Follow the interactive prompts to select what you want to install.

## 📊 What Gets Installed

### Always Installed (Base)
- **Build tools**: git, curl, wget, build-essential, cmake, pkg-config, autoconf, automake
- **Server essentials**: tmux, screen, vim, nano, jq, rsync, socat, net-tools, dnsutils, mtr-tiny
- **Monitoring**: htop, btop, iotop, iftop, ncdu, sysstat, nload
- **Security**: fail2ban (SSH protection), gnupg2
- **System**: logrotate, cron, neofetch, tree, zip/unzip, pass

### Optional (Selected via Prompts)

| Category | Component | What's Included |
|----------|-----------|----------------|
| **Server** | Hostname | Custom hostname configuration |
| | Timezone | Interactive timezone setup |
| | Swap | Configurable swap file (e.g. 1G, 2G, 4G) |
| | SSH Hardening | Root login disabled, password auth toggle, max auth tries |
| | UFW | Firewall with SSH, HTTP, HTTPS rules |
| | Auto-updates | unattended-upgrades for automatic security patches |
| **Dev** | Python | Python 3, pip, venv, dev headers |
| | Java | OpenJDK 17 (JDK & JRE) |
| | Go | Go 1.23.6 |
| | Node.js | NVM + LTS Node.js + yarn, typescript, nodemon, pm2 |
| | C/C++ | gcc, g++, gdb, clang, valgrind |
| | Docker | Docker Engine + Docker Compose plugin |
| | Miniconda | Python environment management |
| **Software** | Nginx | Nginx web server |
| | Cloudflared | Cloudflare Tunnel client |
| | Monitoring | glances, bpytop, nload, lm-sensors |

## ⚙️ Post-Installation Steps

After the script completes:

1. **Reload your shell**:
   ```bash
   source ~/.bashrc
   ```

2. **Docker** (if installed):
   ```bash
   newgrp docker
   docker run hello-world
   ```

3. **Nginx** (if installed):
   ```bash
   # Check status
   sudo systemctl status nginx
   # Visit http://your-server-ip
   ```

4. **Cloudflare Tunnel** (if installed):
   ```bash
   cloudflared tunnel login
   cloudflared tunnel create <tunnel-name>
   ```

5. **Security**:
   ```bash
   sudo fail2ban-client status
   sudo ufw status verbose
   ```

6. **Monitoring**:
   ```bash
   htop          # Process monitoring
   glances       # System overview
   bpytop        # Resource monitor
   nload         # Network bandwidth
   sudo iotop    # Disk I/O
   sudo iftop    # Network traffic
   ncdu          # Disk usage analyzer
   tmux          # Terminal multiplexer
   ```

7. **System Logs**:
   ```bash
   ls ~/system_logs/
   ```

## 🛡️ Security Considerations

- SSH hardening option: disables root login, configures password authentication, limits auth attempts
- Fail2ban is automatically installed and configured for SSH protection
- UFW firewall can be enabled with basic rules (SSH, HTTP, HTTPS)
- Automatic security updates via unattended-upgrades (optional)

For production environments, we additionally recommend:
- Using SSH keys only (disable password auth during setup)
- Setting up additional firewall rules based on your specific needs
- Configuring log monitoring and alerting

## 📁 System Logs Directory

The script creates a `~/system_logs` directory containing:
- `setup_complete_date.log` - Installation timestamp
- `system_info.log` - OS and kernel information
- `cpu_info.log` - CPU details
- `memory_info.log` - Memory configuration
- `disk_info.log` - Disk usage
- `network_info.log` - Network configuration
- `docker_info.log` - Docker system info (if installed)
- `nexuscore_config.log` - Record of what was installed