<div align="center">

[![Ubuntu Version](https://img.shields.io/badge/Ubuntu-24.04.2_LTS-orange.svg)](https://ubuntu.com/)
[![Bash Script](https://img.shields.io/badge/Bash-Script-brightgreen.svg)](https://www.gnu.org/software/bash/)
[![Version](https://img.shields.io/badge/Version-3.0-blue.svg)](https://github.com/djdiptayan1/NexusCore)

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

> A simplified Ubuntu 24.04 LTS server provisioning toolkit with interactive setup

## 📋 Overview

NexusCore is a streamlined server setup script for Ubuntu 24.04 LTS. It uses interactive prompts to let you choose exactly what to install — perfect for first-time setup of bare metal servers, VPS instances (Hostinger, DigitalOcean, etc.), or any fresh Ubuntu server.

## 🔧 Features

### Interactive Setup
- ✅ Choose what to install at runtime via simple yes/no prompts
- ✅ Single-user focused setup (uses current user)
- ✅ No GPU drivers or complex multi-user configuration

### System Configuration
- ✅ System update and package upgrade
- ✅ SSH configuration and security
- ✅ UFW (Uncomplicated Firewall) setup
- ✅ Essential system utilities

### Development Environment
- ✅ Multiple programming languages and runtimes:
  - Python 3 with pip, venv, and dev headers
  - OpenJDK 17 (JDK & JRE)
  - Go (Golang)
  - C/C++ toolchain (gcc, g++, gdb, clang)
  - Node.js LTS via NVM (Node Version Manager)
- ✅ Miniconda for Python environment management
- ✅ Docker and Docker Compose

### Additional Tools
- ✅ System monitoring utilities (htop, glances, bpytop)
- ✅ Cloudflared for Cloudflare Tunnel setup
- ✅ Fail2ban for SSH brute-force protection
- ✅ Automatic system logs collection

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
- git, curl, wget
- build-essential, cmake, pkg-config
- software-properties-common
- apt-transport-https, ca-certificates, gnupg, lsb-release
- zip/unzip, tree, ncdu, pass
- neofetch, htop, btop
- fail2ban (SSH protection)

### Optional (Selected via Prompts)

| Component | What's Included |
|-----------|----------------|
| **Python** | Python 3, pip, venv, virtualenv, dev headers |
| **Java** | OpenJDK 17 (JDK & JRE) |
| **Go** | Go 1.23.6 |
| **Node.js** | NVM + LTS Node.js + yarn, typescript, nodemon, pm2 |
| **C/C++** | gcc, g++, gdb, clang, valgrind |
| **Docker** | Docker Engine + Docker Compose plugin |
| **Miniconda** | Python environment management |
| **Cloudflared** | Cloudflare Tunnel client |
| **Monitoring** | glances, bpytop, lm-sensors |
| **UFW** | Firewall with SSH, HTTP, HTTPS rules |

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

3. **Cloudflare Tunnel** (if installed):
   ```bash
   cloudflared tunnel login
   cloudflared tunnel create <tunnel-name>
   ```

4. **Security**:
   ```bash
   sudo fail2ban-client status
   sudo ufw status verbose
   ```

## 🛡️ Security Considerations

- SSH password authentication is enabled by default
- Fail2ban is automatically installed and configured for SSH protection
- UFW firewall can be enabled with basic rules (SSH, HTTP, HTTPS)

For production environments, we additionally recommend:
- Disabling password authentication and using SSH keys only
- Setting up additional firewall rules based on your specific needs
- Implementing regular security updates

## 📁 System Logs Directory

The script creates a `~/system_logs` directory containing:
- `setup_complete_date.log` - Installation timestamp