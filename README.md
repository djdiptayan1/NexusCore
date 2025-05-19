# NexusCore - Advanced Ubuntu Server Setup Toolkit

[![Ubuntu Version](https://img.shields.io/badge/Ubuntu-24.04.2_LTS-orange.svg)](https://ubuntu.com/)
[![Bash Script](https://img.shields.io/badge/Bash-Script-brightgreen.svg)](https://www.gnu.org/software/bash/)
[![Version](https://img.shields.io/badge/Version-2.1-blue.svg)](https://github.com/djdiptayan1/NexusCore)

> A comprehensive Ubuntu 24.04 LTS server provisioning and configuration toolkit

## 📋 Overview

NexusCore is an advanced server setup script for Ubuntu 24.04 LTS that configures a complete development and deployment environment with best practices. This toolkit automates the initial server setup process, security configurations, and installs essential development tools and runtime environments.

## 🔧 Features

### System Configuration
- ✅ System update and package upgrade
- ✅ SSH configuration and security
- ✅ UFW (Uncomplicated Firewall) setup
- ✅ Essential system utilities and monitoring tools

### Development Environment
- ✅ Complete development toolchain (build-essential, cmake, etc.)
- ✅ Multiple programming languages and runtimes:
  - Python 3 with pip, venv, and dev headers
  - OpenJDK 17 (JDK & JRE)
  - C/C++ toolchain (gcc, g++, gdb, clang)
  - Node.js LTS via NVM (Node Version Manager)
- ✅ Miniconda for Python environment management
- ✅ Docker and Docker Compose

### Additional Tools
- ✅ System monitoring utilities (htop, glances, bpytop, etc.)
- ✅ Cloudflared for Cloudflare Tunnel setup
- ✅ Network and hardware diagnostic tools
- ✅ Automatic system logs collection
- ✅ Fail2ban for SSH brute-force protection

## 🚀 Quick Start

### Prerequisites
- A clean Ubuntu 24.04.2 LTS installation
- A user account with sudo privileges

### Installation

1. Clone this repository or download the setup script:
   ```bash
   git clone https://github.com/djdiptayan1/NexusCore.git
   cd NexusCore
   ```

2. Configure the script to suit your needs (optional):
   ```bash
   # Edit the script configuration variables at the top
   nano setup_nexuscore.sh
   ```

   Key configuration options:
   ```bash
   # Change these variables to match your preferences
   ADMIN_USER="djdiptayan"
   JAVA_VERSION="17"
   INSTALL_DOCKER=true
   INSTALL_PYTHON=true
   INSTALL_MINICONDA=true
   # ...and more options
   ```

3. Make the script executable:
   ```bash
   chmod +x setup_nexuscore.sh
   ```

4. Run the script:
   ```bash
   ./setup_nexuscore.sh
   ```

5. Follow the post-installation steps displayed at the end of the script execution.

## 📊 What Gets Installed

### System Utilities
- git, curl, wget
- build-essential, cmake, pkg-config
- software-properties-common
- apt-transport-https, ca-certificates, gnupg, lsb-release
- zip/unzip, tree, ncdu, pass
- neofetch

### Programming Languages & Runtimes
- **Python**: Python 3 with pip, venv, virtualenv, pipenv, ipython, and development headers
- **Java**: OpenJDK 17 (JDK & JRE)
- **C/C++**: gcc, g++, gdb, clang, valgrind
- **Node.js**: NVM with latest LTS version, plus global packages (yarn, typescript, ts-node, nodemon, pm2)

### Container & Environment Management
- **Docker**: Docker Engine and Docker Compose plugin
- **Miniconda**: Python environment management

### Monitoring & Diagnostics
- htop, glances, bpytop
- iotop, iftop
- radeontop (GPU monitoring)
- lm-sensors (hardware monitoring)

### Networking & Security
- UFW (Uncomplicated Firewall) with pre-configured rules
- SSH server with password authentication (configurable)
- Fail2ban pre-configured for SSH protection
- Cloudflared for Cloudflare Tunnel setup

## ⚙️ Post-Installation Steps

After the script completes, a comprehensive guide with starter commands will be displayed. Here's a summary:

1. **Shell Environment Setup**:
   ```bash
   # Apply NVM & Conda to current session
   source ~/.bashrc
   ```

2. **Docker Permissions**:
   ```bash
   # Option 1: Log out and log back in
   # Option 2: Start a new shell with the docker group
   newgrp docker
   
   # Test your Docker installation
   docker run hello-world
   ```

3. **Monitoring Tools**:
   ```bash
   # Hardware sensor detection (interactive)
   sudo sensors-detect
   
   # View hardware temperatures
   sensors
   
   # CPU and process monitoring
   htop
   
   # Advanced system monitoring
   glances
   
   # Pretty resource monitor
   bpytop
   
   # Monitor disk I/O
   sudo iotop
   
   # Network usage monitor
   sudo iftop
   
   # Disk usage analyzer
   ncdu
   ```

4. **Security Tools**:
   ```bash
   # Check fail2ban status
   sudo fail2ban-client status
   
   # Generate SSH key
   ssh-keygen -t ed25519 -C "your_email@example.com"
   
   # Check firewall status
   sudo ufw status verbose
   
   # Monitor auth logs
   sudo tail -f /var/log/auth.log
   ```

5. **Cloudflare Tunnel Setup**:
   ```bash
   # Login to Cloudflare
   cloudflared tunnel login
   
   # Create a new tunnel
   cloudflared tunnel create <tunnel-name>
   
   # Configure tunnel
   nano ~/.cloudflared/config.yml
   
   # Run your tunnel
   cloudflared tunnel run <tunnel-name>
   ```

6. **System Logs**:
   ```bash
   # View collected system logs
   ls -la ~/system_logs
   ```

## 🛡️ Security Considerations

- The script configures SSH with password authentication (can be disabled with `ENABLE_PASSWORD_AUTH=false`)
- Fail2ban is automatically installed and configured to protect SSH from brute force attacks
- UFW firewall is enabled with basic rules (SSH, HTTP, HTTPS)

For production environments, we additionally recommend:
- Disabling password authentication and using SSH keys only
- Setting up additional firewall rules based on your specific needs
- Implementing regular security updates
- Configuring logging and monitoring

## 🔄 Customization

The script offers flexible configuration through variables at the top:

```bash
# --- Configuration ---
ADMIN_USER="djdiptayan"        # Your username
JAVA_VERSION="17"              # Java version to install
INSTALL_DOCKER=true            # Enable/disable Docker installation
INSTALL_PYTHON=true            # Enable/disable Python installation
INSTALL_MINICONDA=true         # Enable/disable Miniconda installation
INSTALL_JAVA=true              # Enable/disable Java installation  
INSTALL_CPP=true               # Enable/disable C/C++ toolchain
INSTALL_NODEJS=true            # Enable/disable Node.js installation
INSTALL_CLOUDFLARED=true       # Enable/disable Cloudflared installation
INSTALL_MONITORING_TOOLS=true  # Enable/disable monitoring tools
SETUP_UFW=true                 # Enable/disable firewall setup
ENABLE_PASSWORD_AUTH=true      # Enable/disable SSH password auth
```

Additional customization options:
- UFW rules: Add or remove ports as needed for your applications
- fail2ban configuration: Adjust in `/etc/fail2ban/jail.d/sshd.conf`
- Add additional packages or configurations as required

## 📁 System Logs Directory

The script creates a `~/system_logs` directory containing:
- `setup_complete_date.log` - Installation timestamp
- `system_info.log` - Basic system information
- `cpu_info.log` - Detailed CPU information
- `memory_info.log` - Memory configuration
- `disk_info.log` - Disk usage
- `network_info.log` - Network configuration
- `docker_info.log` - Docker system information (if installed)

This can be useful for system documentation and troubleshooting.

## 🖥️ Interactive Toolkit Output

Upon completion, the script will display a comprehensive, color-coded guide with:

1. **System Information**:
   - Hostname and IP addresses
   - Detailed system summary via neofetch
   - CPU specifications
   - Memory usage
   - Disk space information

2. **Command Reference**:
   - Color-coded commands for all installed tools
   - Step-by-step instructions for post-installation actions
   - Testing commands to verify installations
   
This interactive guide is designed to be your quick-reference manual for getting started with your newly configured server.